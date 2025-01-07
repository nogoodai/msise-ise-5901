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
  description = "Stack name for resource naming"
  default     = "my-todo-app"
}

variable "application_name" {
  description = "Application name for resource naming"
  default     = "todo-app"
}

variable "github_repository" {
  description = "GitHub repository for Amplify app"
  default     = "myorg/my-todo-app"
}

# Provider
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app_user_pool" {
  name = "${var.stack_name}-user-pool"

  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.todo_app_user_pool.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  generate_secret                      = false

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "todo_app_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_app_user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-api"
  description = "API for Todo App"
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app_user_pool.arn]
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.stack_name}-api-deployment"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "todo_api_usage_plan" {
  name         = "${var.stack_name}-api-usage-plan"
  description  = "Usage plan for Todo API"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_api_deployment.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.stack_name}-api-usage-plan"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "todo_lambda" {
  for_each = toset(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"])

  function_name = "${var.stack_name}-${each.key}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  filename      = "lambda_functions/${each.key}.zip"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-${each.key}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Lambda Permissions for API Gateway
resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  for_each      = aws_lambda_function.todo_lambda
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repository

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
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify Branch
resource "aws_amplify_branch" "todo_app_master_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-master-branch"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Roles and Policies
# API Gateway Role
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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
    Name        = "${var.stack_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name   = "${var.stack_name}-api-gateway-policy"
  role   = aws_iam_role.api_gateway_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/api-gateway/*"
      }
    ]
  })
}

# Amplify Role
resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

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
    Name        = "${var.stack_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name   = "${var.stack_name}-amplify-policy"
  role   = aws_iam_role.amplify_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "amplify:*"
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Lambda Role
resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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
    Name        = "${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.stack_name}-lambda-policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "dynamodb:*"
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      },
      {
        Action   = "cloudwatch:PutMetricData"
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  for_each = aws_lambda_function.todo_lambda

  alarm_name          = "${each.value.function_name}-Errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${each.value.function_name}-Errors"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.todo_api.id}"
  retention_in_days = 7

  tags = {
    Name        = "api-gateway-logs"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.todo_app_user_pool.id
  description = "Cognito User Pool ID"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.todo_app_client.id
  description = "Cognito User Pool Client ID"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.todo_app_domain.domain
  description = "Cognito User Pool Domain"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "DynamoDB Table Name"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.todo_api.id
  description = "API Gateway ID"
}

output "api_gateway_url" {
  value       = aws_api_gateway_deployment.todo_api_deployment.invoke_url
  description = "API Gateway URL"
}

output "amplify_app_id" {
  value       = aws_amplify_app.todo_app.id
  description = "Amplify App ID"
}

output "amplify_app_url" {
  value       = aws_amplify_app.todo_app.default_domain
  description = "Amplify App URL"
}

# Data Sources
data "aws_caller_identity" "current" {}
