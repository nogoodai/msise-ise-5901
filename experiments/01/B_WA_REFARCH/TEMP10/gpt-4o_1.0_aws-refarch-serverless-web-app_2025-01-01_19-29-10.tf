terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources into."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the application stack."
  default     = "my-stack"
}

variable "cognito_user_pool_domain" {
  description = "Custom domain prefix for Cognito User Pool."
  default     = "myapp"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                   = "client-${var.stack_name}"
  user_pool_id           = aws_cognito_user_pool.user_pool.id
  generate_secret        = false
  allowed_oauth_flows    = ["code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain      = "${var.cognito_user_pool_domain}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  partition_key {
    name = "cognito-username"
    type = "S"
  }

  sort_key {
    name = "id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
    allow_origins = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format          = "$context.requestId"
  }
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name = "/aws/apigateway/${var.stack_name}-logging"
  retention_in_days = 7
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id       = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.client.id]
    issuer   = aws_cognito_user_pool.user_pool.endpoint
  }

  name = "CognitoAuthorizer"
}

resource "aws_apigatewayv2_api_mapping" "mapping" {
  api_id      = aws_apigatewayv2_api.api.id
  domain_name = aws_cognito_user_pool_domain.domain.domain
  stage       = aws_apigatewayv2_stage.api_stage.name
}

resource "aws_lambda_function" "lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "lambda-${var.stack_name}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role-${var.stack_name}"

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

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy_${var.stack_name}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:*",
          "logs:*",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "amplify_app" {
  name        = "amplify-${var.stack_name}"
  repository  = "https://github.com/user/repository"

  build_spec = <<BUILD_SPEC
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*    
BUILD_SPEC
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api_gateway_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "apigateway_cloudwatch_policy" {
  name = "apigateway_cloudwatch_policy_${var.stack_name}"
  role = aws_iam_role.api_gateway_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*",
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "lambda_function_name" {
  value = aws_lambda_function.lambda.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
