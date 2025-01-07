terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack."
  default     = "prod"
}

variable "application_name" {
  description = "The name of the application."
  default     = "todo-app"
}

variable "github_repository" {
  description = "The GitHub repository for the Amplify app."
}

resource "aws_cognito_user_pool" "auth_pool" {
  name                      = "${var.application_name}-${var.stack_name}-user-pool"
  auto_verified_attributes  = ["email"]
  username_attributes       = ["email"]
  password_policy {
    minimum_length                   = 6
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = false
    require_symbols                  = false
  }
}

resource "aws_cognito_user_pool_client" "auth_client" {
  user_pool_id = aws_cognito_user_pool.auth_pool.id
  generate_secret = false
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_ADMIN_NO_SRP_AUTH"]
  o_auth_flows = ["code", "implicit"]
  allowed_o_auth_scopes = ["openid", "email", "phone"]
}

resource "aws_cognito_user_pool_domain" "auth_domain" {
  domain      = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.auth_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  hash_key       = "cognito-username"
  range_key      = "id"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

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

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API for ${var.application_name}"
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  xray_tracing_enabled = true
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = "${var.stack_name}"
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.application_name}-${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "crud" {
  function_name = "${var.application_name}-${var.stack_name}-crud"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_exec_role.arn

  # Add the S3 bucket and object key for your Lambda deployment package
  # s3_bucket = "your-s3-bucket"
  # s3_key    = "lambda-package.zip"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-exec-role"
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

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name   = "${var.application_name}-${var.stack_name}-lambda-dynamodb-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:*"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = "logs:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "frontend" {
  name = "${var.application_name}-${var.stack_name}-frontend"

  repository = var.github_repository

  build_spec = <<EOF
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - yarn install
    build:
      commands:
        - yarn build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  oauth_token = var.github_oauth_token
}

resource "aws_amplify_branch" "master" {
  app_id   = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-role"
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

resource "aws_iam_role_policy" "api_gateway_policy" {
  name   = "${var.application_name}-${var.stack_name}-api-gateway-policy"
  role   = aws_iam_role.api_gateway_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:PutLogEvents"
        Resource = "*"
      },
    ]
  })
}

output "user_pool_id" {
  value = aws_cognito_user_pool.auth_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
