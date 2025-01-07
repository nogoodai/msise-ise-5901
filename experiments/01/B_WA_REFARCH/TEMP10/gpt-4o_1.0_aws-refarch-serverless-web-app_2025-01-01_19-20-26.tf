terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name to use for naming resources."
  default     = "prod"
}

variable "cognito_domain_prefix" {
  description = "The custom domain prefix for the Cognito User Pool domain."
  default     = "myapp-prod"
}

resource "aws_cognito_user_pool" "default" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols = false
    require_numbers = false
  }

  tags = {
    Name       = "user-pool-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_cognito_user_pool_client" "default" {
  user_pool_id       = aws_cognito_user_pool.default.id
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  oauth_flows       = ["code", "implicit"]
  oauth_scopes      = ["email", "phone", "openid"]
  generate_secret   = false

  tags = {
    Name       = "user-pool-client-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_cognito_user_pool_domain" "default" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.default.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

  hash_key  = "cognito-username"
  range_key = "id"

  attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  provisioned_throughput {
    read_capacity  = 5
    write_capacity = 5
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name       = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
  }

  tags = {
    Name       = "api-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "prod"
  auto_deploy = true

  tags = {
    Name       = "api-stage-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id         = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.default.id]
    issuer   = aws_cognito_user_pool.default.endpoint
  }

  tags = {
    Name       = "api-authorizer-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_execution_role.arn

  tags = {
    Name       = "add-item-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_amplify_app" "frontend" {
  name       = "amplify-app-${var.stack_name}"
  repository = "https://github.com/user/repo"
  oauth_token = var.github_token

  build_spec = file("buildspec.yml")

  environment_variables {
    key   = "NODE_ENV"
    value = "production"
  }

  tags = {
    Name       = "amplify-app-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name       = "amplify-branch-master-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name       = "lambda-execution-role-${var.stack_name}"
    Environment = var.stack_name
    Project    = "ServerlessApp"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda-policy-${var.stack_name}"
  role   = aws_iam_role.lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = "xray:PutTraceSegments"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

output "user_pool_id" {
  value = aws_cognito_user_pool.default.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "frontend_url" {
  value = aws_amplify_app.frontend.default_domain
}
