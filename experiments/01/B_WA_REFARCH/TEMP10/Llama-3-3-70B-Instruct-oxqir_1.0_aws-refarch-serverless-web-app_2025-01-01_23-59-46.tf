provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "Application name"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment name"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
  description = "Stack name"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_pool" {
  name                = "${var.application_name}-${var.stack_name}-user-pool"
  email_configuration {
    email_verifying_message = "Please verify your email address"
  }
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  username_attributes = ["email"]
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_client" {
  name                = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_pool.id
  supported_identity_providers = ["COGNITO"]
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH", "CUSTOM_AUTH_FLOW_ONLY", "USER_SRP_AUTH"]
  generate_secret     = false
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.environment
    Project     = var.application_name
  }
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_domain" {
  domain       = "${var.application_name}-${var.stack_name}.auth.us-west-2amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.todo_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "${var.application_name}-${var.stack_name}-todo-table"
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
  read_capacity_units  = 5
  write_capacity_units = 5
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-todo-table"
    Environment = var.environment
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API for todo app"
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name        = "${var.application_name}-${var.stack_name}-authorizer"
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_pool.arn]
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_get_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_integration" "todo_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_get_lambda.arn}/invocations"
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_integration.todo_get_integration]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = var.environment
}

# Lambda Functions
resource "aws_lambda_function" "todo_get_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-todo-get-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-todo-get-lambda"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "todo_post_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-todo-post-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-todo-post-lambda"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "todo_put_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-todo-put-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-todo-put-lambda"
    Environment = var.environment
    Project     = var.application_name
  }
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.application_name}-${var.stack_name}-amplify-app"
  description = "Amplify app for todo app"
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"
}

# IAM Roles and Policies
resource "aws_iam_role" "todo_lambda_role" {
  name        = "${var.application_name}-${var.stack_name}-lambda-role"
  description = "IAM role for lambda functions"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-role"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "todo_lambda_policy" {
  name        = "${var.application_name}-${var.stack_name}-lambda-policy"
  description = "IAM policy for lambda functions"
  policy      = jsonencode({
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-policy"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_lambda_policy_attach" {
  role       = aws_iam_role.todo_lambda_role.name
  policy_arn = aws_iam_policy.todo_lambda_policy.arn
}

resource "aws_iam_role" "todo_api_gateway_role" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-role"
  description = "IAM role for API Gateway"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-role"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "todo_api_gateway_policy" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
  description = "IAM policy for API Gateway"
  policy      = jsonencode({
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
      },
    ]
  })
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_api_gateway_policy_attach" {
  role       = aws_iam_role.todo_api_gateway_role.name
  policy_arn = aws_iam_policy.todo_api_gateway_policy.arn
}

resource "aws_iam_role" "todo_amplify_role" {
  name        = "${var.application_name}-${var.stack_name}-amplify-role"
  description = "IAM role for Amplify"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-role"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "todo_amplify_policy" {
  name        = "${var.application_name}-${var.stack_name}-amplify-policy"
  description = "IAM policy for Amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-policy"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_amplify_policy_attach" {
  role       = aws_iam_role.todo_amplify_role.name
  policy_arn = aws_iam_policy.todo_amplify_policy.arn
}

output "cognito_user_pool_arn" {
  value = aws_cognito_user_pool.todo_pool.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_pool.id
}

output "cognito_user_pool_name" {
  value = aws_cognito_user_pool.todo_pool.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "dynamodb_table_id" {
  value = aws_dynamodb_table.todo_table.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "api_gateway_rest_api_name" {
  value = aws_api_gateway_rest_api.todo_api.name
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.todo_deployment.stage_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.todo_get_lambda.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.todo_get_lambda.function_name
}

output "amplify_app_arn" {
  value = aws_amplify_app.todo_app.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_app_name" {
  value = aws_amplify_app.todo_app.name
}
