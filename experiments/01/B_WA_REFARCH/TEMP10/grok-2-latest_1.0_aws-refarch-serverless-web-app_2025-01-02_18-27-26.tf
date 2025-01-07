terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Stack name used in resource naming"
  default     = "todo-app"
}

variable "application_name" {
  description = "Application name"
  default     = "todo"
}

variable "domain_name" {
  description = "Custom domain name for Cognito"
  default     = "auth.todo.example.com"
}

# Provider
provider "aws" {
  region = var.region
}

# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_client" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.todo_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                  = ["email", "phone", "openid"]
  callback_urls                         = ["https://${var.domain_name}/"]
  logout_urls                           = ["https://${var.domain_name}/logout"]
  supported_identity_providers          = ["COGNITO"]
  prevent_user_existence_errors         = "ENABLED"
  enable_token_revocation               = true
  allow_admin_user_password_auth        = false
  enable_propagate_additional_user_context_data = true

  tags = {
    Name        = "${var.application_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Custom Domain for Cognito
resource "aws_cognito_user_pool_domain" "todo_domain" {
  domain       = var.domain_name
  user_pool_id = aws_cognito_user_pool.todo_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "cognito-username"
  range_key      = "id"

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

  tags = {
    Name        = "${var.application_name}-dynamodb-table"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API for todo application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_method_settings" "todo_method_settings" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = aws_api_gateway_deployment.todo_deployment.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = true
  }
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name                   = "${var.application_name}-${var.stack_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.todo_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.todo_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name        = "${var.application_name}-${var.stack_name}-usage-plan"
  description = "Usage plan for todo API"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
  }

  quota_settings {
    limit  = 5000
    offset = 0
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
locals {
  lambda_functions = [
    "add-item",
    "get-item",
    "get-all-items",
    "update-item",
    "complete-item",
    "delete-item"
  ]
}

resource "aws_lambda_function" "todo_lambda" {
  for_each = toset(local.lambda_functions)

  function_name = "${var.application_name}-${var.stack_name}-${each.value}"
  handler       = "${each.value}.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename      = "lambda-${each.value}.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-${each.value}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-role"

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
    Name        = "${var.application_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.application_name}-${var.stack_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = "https://github.com/your-github-username/todo-frontend"

  build_spec = <<-EOT
    version: 0.1
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  tags = {
    Name        = "${var.application_name}-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.application_name}-branch"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Role for API Gateway
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

  tags = {
    Name        = "${var.application_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-${var.stack_name}-amplify-role"

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
    Name        = "${var.application_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.application_name}-${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "amplify:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Monitoring and Alerting
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  for_each = toset(local.lambda_functions)

  alarm_name          = "${var.application_name}-${var.stack_name}-${each.value}-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${each.value}"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.todo_lambda[each.value].function_name
  }

  tags = {
    Name        = "${var.application_name}-${each.value}-error-alarm"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.todo_pool.id
  description = "Cognito User Pool ID"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.todo_client.id
  description = "Cognito User Pool Client ID"
}

output "cognito_user_pool_domain" {
  value       = aws_cognito_user_pool_domain.todo_domain.domain
  description = "Cognito User Pool Domain"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "DynamoDB Table Name"
}

output "api_gateway_url" {
  value       = aws_api_gateway_deployment.todo_deployment.invoke_url
  description = "API Gateway URL"
}

output "amplify_app_url" {
  value       = aws_amplify_app.todo_app.default_domain
  description = "Amplify App URL"
}
