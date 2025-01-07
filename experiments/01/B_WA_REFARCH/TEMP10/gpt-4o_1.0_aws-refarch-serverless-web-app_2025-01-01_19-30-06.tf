terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  default = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack used in naming resources."
  type        = string
  default     = "my-app-stack"
}

variable "github_repo" {
  description = "The GitHub repository for Amplify app source."
  type        = string
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  attributes {
    name = "email"
  }

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "client-${var.stack_name}"

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain          = "${var.stack_name}.example.com"
  user_pool_id    = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

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

  server_side_encryption {
    enabled = true
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "api" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "authorizer" {
  api_id          = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience      = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer        = aws_cognito_user_pool.user_pool.endpoint
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "prod"
  auto_deploy = true
}

resource "aws_apigatewayv2_api_mapping" "api_mapping" {
  api_id      = aws_apigatewayv2_api.api.id
  domain_name = var.stack_name
  stage       = aws_apigatewayv2_stage.api_stage.name
}

# Lambda Functions
locals {
  lambda_execution_role_name = "lambda_execution_role_${var.stack_name}"
}

resource "aws_iam_role" "lambda_execution_role" {
  name = local.lambda_execution_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda_policy_${var.stack_name}"
  role   = aws_iam_role.lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:*",
          "cloudwatch:*",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "lambda" {
  filename         = "function.zip"
  function_name    = "lambda-${var.stack_name}"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tracing_config {
    mode = "Active"
  }
}

# Amplify
resource "aws_amplify_app" "amplify_app" {
  name        = "amplify-${var.stack_name}"
  repository  = var.github_repo
  oauth_token = "github-oauth-token"

  build_spec = file("amplify-buildspec.yml")
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

# IAM Roles and Policies for API Gateway and Amplify
resource "aws_iam_role" "api_gateway_role" {
  name = "api_gateway_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name   = "api_gateway_policy_${var.stack_name}"
  role   = aws_iam_role.api_gateway_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["arn:aws:logs:*:*:log-group:/aws/apigateway/*"]
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "amplify_policy" {
  name   = "amplify_policy_${var.stack_name}"
  role   = aws_iam_role.amplify_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "amplify:*"
        Resource = "*"
      }
    ]
  })
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "lambda_function_arn" {
  value = aws_lambda_function.lambda.arn
}

output "api_gateway_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
