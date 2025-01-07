terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack"
  default     = "todo-app"
}

variable "application_name" {
  description = "Name of the application"
  default     = "todo-app"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the custom domain for Cognito"
  default     = "auth"
}

variable "github_owner" {
  description = "GitHub owner of the repository"
  default     = "user"
}

variable "github_repo" {
  description = "GitHub repository name"
  default     = "todo-frontend"
}

variable "github_branch" {
  description = "GitHub branch to deploy"
  default     = "master"
}

# Provider configuration for AWS
provider "aws" {
  region = var.region
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "user_pool" {
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
    Environment = "production"
    Project     = var.application_name
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                   = ["code", "implicit"]
  allowed_oauth_scopes                  = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = var.application_name
  }
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB table for data storage with partition and sort keys
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
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "api_gateway_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.application_name} API"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.api_gateway_deployment.stage_name
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

  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "production"
    Project     = var.application_name
  }
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "lambda_function" {
  for_each = toset(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"])

  function_name = "${var.stack_name}-${each.key}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  role = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-${each.key}"
    Environment = "production"
    Project     = var.application_name
  }
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "amplify_app" {
  name       = "${var.stack_name}-frontend"
  repository = "https://github.com/${var.github_owner}/${var.github_repo}"

  build_spec = <<-EOT
    version: 0.1
    frontend:
      phases:
        build:
          commands:
            - npm install
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
    Name        = "${var.stack_name}-frontend"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = var.github_branch

  framework = "React"
  stage     = "PRODUCTION"

  enable_auto_build = true
}

# IAM roles and policies for API Gateway, Amplify, and Lambda
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
    Environment = "production"
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
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

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
    Environment = "production"
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
        Action   = ["amplify:*"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

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
    Environment = "production"
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
        Action   = ["dynamodb:*"]
        Effect   = "Allow"
        Resource = "${aws_dynamodb_table.todo_table.arn}"
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action   = ["cloudwatch:PutMetricData"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Logs and Alarms
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.api_gateway.name}"
  retention_in_days = 30

  tags = {
    Name        = "/aws/api-gateway/${aws_api_gateway_rest_api.api_gateway.name}"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = aws_lambda_function.lambda_function

  name              = "/aws/lambda/${each.value.function_name}"
  retention_in_days = 30

  tags = {
    Name        = "/aws/lambda/${each.value.function_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors_alarm" {
  for_each = aws_lambda_function.lambda_function

  alarm_name          = "${each.value.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors errors for ${each.value.function_name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${each.value.function_name}-errors"
    Environment = "production"
    Project     = var.application_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.api_gateway_deployment.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}
