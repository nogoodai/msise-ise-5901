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
  description = "The name of the stack"
  default     = "todo-app"
}

variable "application_name" {
  description = "The name of the application"
  default     = "todo-app"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  default     = "username/todo-frontend"
}

variable "github_token" {
  description = "GitHub token for Amplify"
  default     = ""
}

# Provider configuration
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length  = 6
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
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.application_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                   = ["code", "implicit"]
  allowed_oauth_scopes                  = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.application_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api"
  description = "API for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_deployment.deployment.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.application_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.application_name}-usage-plan"
  description = "Usage plan for ${var.application_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.application_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_functions/add_item.zip"

  role = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-add-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.application_name}-get-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_functions/get_item.zip"

  role = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-get-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.application_name}-get-all-items"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_functions/get_all_items.zip"

  role = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-get-all-items"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.application_name}-update-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_functions/update_item.zip"

  role = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-update-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.application_name}-complete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_functions/complete_item.zip"

  role = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-complete-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.application_name}-delete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_functions/delete_item.zip"

  role = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-delete-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name       = "${var.application_name}-frontend"
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

  environment_variables = {
    ENV = var.stack_name
  }

  tags = {
    Name        = "${var.application_name}-frontend"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.application_name}-master-branch"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

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
  name = "${var.application_name}-api-gateway-policy"
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
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/api-gateway/*:log-stream:*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-amplify-role"

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
  name = "${var.application_name}-amplify-policy"
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
  name = "${var.application_name}-lambda-role"

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
  name = "${var.application_name}-lambda-policy"
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
        Action   = "cloudwatch:PutMetricData"
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Logs and Alarms
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.api.name}"
  retention_in_days = 30

  tags = {
    Name        = "${aws_api_gateway_rest_api.api.name}-log-group"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  alarm_name          = "${var.application_name}-api-gateway-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.api.name
    Stage   = aws_api_gateway_deployment.deployment.stage_name
  }

  tags = {
    Name        = "${var.application_name}-api-gateway-5xx-errors"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = toset([
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.update_item.function_name,
    aws_lambda_function.complete_item.function_name,
    aws_lambda_function.delete_item.function_name
  ])

  name              = "/aws/lambda/${each.value}"
  retention_in_days = 30

  tags = {
    Name        = "${each.value}-log-group"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset([
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.update_item.function_name,
    aws_lambda_function.complete_item.function_name,
    aws_lambda_function.delete_item.function_name
  ])

  alarm_name          = "${each.value}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors for ${each.value}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value
  }

  tags = {
    Name        = "${each.value}-errors"
    Environment = var.stack_name
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

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.amplify_app.default_domain
}
