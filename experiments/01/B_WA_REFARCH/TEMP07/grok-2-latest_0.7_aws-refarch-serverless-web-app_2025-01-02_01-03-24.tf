terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "aws_region" {
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "app_name" {
  description = "Name of the application"
  default     = "todo-app"
}

variable "stack_name" {
  description = "Name of the stack"
  default     = "prod"
}

variable "cognito_domain" {
  description = "Custom domain for Cognito"
  default     = "auth.example.com"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  default     = "your-org/your-repo"
}

# Provider
provider "aws" {
  region = var.aws_region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.app_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "${var.app_name}-user-pool"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.app_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["https://${var.cognito_domain}/"]
  logout_urls                          = ["https://${var.cognito_domain}/"]
  supported_identity_providers         = ["COGNITO"]

  tags = {
    Name        = "${var.app_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.cognito_domain
  user_pool_id = aws_cognito_user_pool.main.id
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
    Name        = "todo-table"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.app_name}-${var.stack_name}-api"
  description = "Todo API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.app_name}-api"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name        = "${var.app_name}-${var.stack_name}-usage-plan"
  description = "Usage plan for Todo API"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
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
    Name        = "${var.app_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.app_name}-${var.stack_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.todo_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.main.arn]
  identity_source        = "method.request.header.Authorization"
}

# Lambda Functions
resource "aws_lambda_function" "todo_lambda" {
  for_each = toset(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"])

  function_name = "${var.app_name}-${var.stack_name}-${each.key}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.app_name}-${each.key}"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.app_name}-${var.stack_name}-lambda-role"

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
    Name        = "${var.app_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.app_name}-${var.stack_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name       = "${var.app_name}-${var.stack_name}-app"
  repository = var.github_repo

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
    Name        = "${var.app_name}-app"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.app_name}-master-branch"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.app_name}-${var.stack_name}-api-gateway-role"

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
    Name        = "${var.app_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.app_name}-${var.stack_name}-api-gateway-policy"
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
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/apigateway/*:*"
      }
    ]
  })
}

# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name = "${var.app_name}-${var.stack_name}-amplify-role"

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
    Name        = "${var.app_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.app_name}-${var.stack_name}-amplify-policy"
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

# CloudWatch Logs and Alarms
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name = "/aws/apigateway/${aws_api_gateway_rest_api.todo_api.name}"

  tags = {
    Name        = "${var.app_name}-api-gateway-logs"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = aws_lambda_function.todo_lambda

  name = "/aws/lambda/${each.value.function_name}"

  tags = {
    Name        = "${var.app_name}-${each.key}-logs"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  for_each = aws_lambda_function.todo_lambda

  alarm_name          = "${each.value.function_name}-ErrorAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${each.value.function_name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${each.value.function_name}-error-alarm"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_app_url" {
  value = aws_amplify_app.todo_app.default_domain
}