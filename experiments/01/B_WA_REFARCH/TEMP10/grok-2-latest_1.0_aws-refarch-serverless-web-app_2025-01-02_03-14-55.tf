terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "project_name" {
  description = "The project name to be used for tagging and naming"
  default     = "todo-app"
}

variable "stack_name" {
  description = "The stack name to be used for tagging and naming"
  default     = "prod"
}

variable "environment" {
  description = "The environment to be used for tagging and naming"
  default     = "production"
}

variable "cognito_domain" {
  description = "Custom domain name for Cognito"
  default     = "auth.todo-app.com"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  default     = "user/todo-app-frontend"
}

# Provider
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
  }

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.project_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  generate_secret                      = false

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = var.cognito_domain
  user_pool_id = aws_cognito_user_pool.user_pool.id
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
    Name        = "${var.project_name}-todo-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.project_name}-${var.stack_name}-api"
  description = "API Gateway for Todo App"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api-gateway"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-api-deployment"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_method_settings" "api_settings" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = aws_api_gateway_deployment.api_deployment.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.project_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name         = "${var.project_name}-${var.stack_name}-usage-plan"
  description  = "Usage plan for API Gateway"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
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
    Name        = "${var.project_name}-usage-plan"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "lambda_functions" {
  for_each = toset(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"])

  function_name = "${var.project_name}-${var.stack_name}-${each.key}"
  runtime       = "nodejs12.x"
  handler       = "${each.key}.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_role.arn

  tags = {
    Name        = "${var.project_name}-${each.key}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name       = "${var.project_name}-${var.stack_name}"
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
    Name        = "${var.project_name}-amplify-app"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.project_name}-amplify-branch"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-role"

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
    Name        = "${var.project_name}-api-gateway-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/api-gateway/*"
      },
      {
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/api-gateway/*:*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-${var.stack_name}-amplify-role"

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
    Name        = "${var.project_name}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.project_name}-${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

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

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.stack_name}-lambda-role"

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
    Name        = "${var.project_name}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-${var.stack_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "dynamodb:*"
        Effect   = "Allow"
        Resource = "${aws_dynamodb_table.todo_table.arn}"
      },
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/*"
      },
      {
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/*:*"
      },
      {
        Action   = "cloudwatch:PutMetricData"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = "xray:PutTraceSegments"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = "xray:PutTelemetryRecords"
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
    Name        = "${var.project_name}-api-gateway-log-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  for_each = aws_lambda_function.lambda_functions

  alarm_name          = "${each.value.function_name}-error-alarm"
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
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_read_capacity" {
  alarm_name          = "${aws_dynamodb_table.todo_table.name}-read-capacity-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ConsumedReadCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "4"
  alarm_description   = "This metric monitors read capacity for ${aws_dynamodb_table.todo_table.name}"
  alarm_actions       = []

  dimensions = {
    TableName = aws_dynamodb_table.todo_table.name
  }

  tags = {
    Name        = "${aws_dynamodb_table.todo_table.name}-read-capacity-alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_write_capacity" {
  alarm_name          = "${aws_dynamodb_table.todo_table.name}-write-capacity-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ConsumedWriteCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "4"
  alarm_description   = "This metric monitors write capacity for ${aws_dynamodb_table.todo_table.name}"
  alarm_actions       = []

  dimensions = {
    TableName = aws_dynamodb_table.todo_table.name
  }

  tags = {
    Name        = "${aws_dynamodb_table.todo_table.name}-write-capacity-alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "lambda_function_arns" {
  value = [for k, v in aws_lambda_function.lambda_functions : v.arn]
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_arn" {
  value = aws_amplify_branch.amplify_branch.arn
}
