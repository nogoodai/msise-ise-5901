provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "project_name" {
  type        = string
  default     = "example-project"
}

variable "stack_name" {
  type        = string
  default     = "example-stack"
}

variable "environment" {
  type        = string
  default     = "prod"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name                     = "${var.project_name}-${var.stack_name}"
  email_verification_message = "Your verification code is {####}. "
  email_configuration = {
    email_sending_account = "COGNITO_DEFAULT"
  }
  admin_create_user_config {
    allow_admin_create_user_only = false
    unused_account_validity_days = 7
  }
  username_attributes      = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.project_name}-${var.stack_name}-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  key_schema = [
    {
      attribute_name = "cognito-username"
      key_type       = "HASH"
    },
    {
      attribute_name = "id"
      key_type       = "RANGE"
    }
  ]
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Role for API Gateway
resource "aws_iam_role" "api_gateway" {
  name        = "${var.project_name}-${var.stack_name}-api-gateway"
  description = "Execution role for API Gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "api_gateway" {
  name        = "${var.project_name}-${var.stack_name}-api-gateway-policy"
  description = "Policy for API Gateway"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-${var.stack_name}"
  description = "API Gateway for ${var.project_name}"
}

resource "aws_api_gateway_resource" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA_PROXY"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.main.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA_PROXY"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.main.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "main" {
  name          = "${var.project_name}-${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
  rest_api_id   = aws_api_gateway_rest_api.main.id
}

# Lambda Function for Add Item
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
  memory_size   = 1024
}

# Lambda Function for Get Item
resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
  memory_size   = 1024
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name        = "${var.project_name}-${var.stack_name}-lambda"
  description = "Execution role for Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda" {
  name        = "${var.project_name}-${var.stack_name}-lambda-policy"
  description = "Policy for Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# Amplify App
resource "aws_amplify_app" "main" {
  name        = "${var.project_name}-${var.stack_name}"
  description = "Amplify App for ${var.project_name}"
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
}

# IAM Role for Amplify
resource "aws_iam_role" "amplify" {
  name        = "${var.project_name}-${var.stack_name}-amplify"
  description = "Execution role for Amplify"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "amplify" {
  name        = "${var.project_name}-${var.stack_name}-amplify-policy"
  description = "Policy for Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "lambda_function_add_item_name" {
  value = aws_lambda_function.add_item.function_name
}

output "lambda_function_get_item_name" {
  value = aws_lambda_function.get_item.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.main.branch_name
}
