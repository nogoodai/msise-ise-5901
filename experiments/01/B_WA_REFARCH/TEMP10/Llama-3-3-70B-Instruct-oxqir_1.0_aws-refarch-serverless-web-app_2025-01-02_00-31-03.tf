provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "application_name" {
  type        = string
  default     = "todo-app"
}

variable "environment" {
  type        = string
  default     = "prod"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/todo-app"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app" {
  name                = "${var.application_name}-${var.environment}-${var.stack_name}"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  username_configuration {
    case_sensitive = true
  }
  alias_attributes = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.application_name}-${var.environment}-${var.stack_name}-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls = ["https://${var.application_name}-${var.environment}-${var.stack_name}.auth.us-west-2.amazoncognito.com"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain       = "${var.application_name}-${var.environment}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_app.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name         = "${var.application_name}-todo-table-${var.environment}-${var.stack_name}"
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
  table_status = "ACTIVE"
  server_side_encryption {
    enabled = true
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_app" {
  name        = "${var.application_name}-${var.environment}-${var.stack_name}"
  description = "Todo App API Gateway"
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  parent_id   = aws_api_gateway_rest_api.todo_app.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
}

# Lambda Function
resource "aws_lambda_function" "todo_app" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  publish       = true
}

# API Gateway Lambda Integration
resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app.arn}/invocations"
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.application_name}-${var.environment}-${var.stack_name}"
  description = "Todo App Amplify App"
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec" {
  name        = "${var.application_name}-${var.environment}-${var.stack_name}-lambda-exec"
  description = "Lambda execution role"

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

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.application_name}-${var.environment}-${var.stack_name}-lambda-policy"
  description = "Lambda execution policy"

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
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.todo_app.region}:${aws_api_gateway_rest_api.todo_app.account_id}:*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.application_name}-${var.environment}-${var.stack_name}-api-gateway-exec"
  description = "API Gateway execution role"

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

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.application_name}-${var.environment}-${var.stack_name}-api-gateway-policy"
  description = "API Gateway execution policy"

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
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.todo_app.region}:${aws_api_gateway_rest_api.todo_app.account_id}:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_app.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.todo_app.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}
