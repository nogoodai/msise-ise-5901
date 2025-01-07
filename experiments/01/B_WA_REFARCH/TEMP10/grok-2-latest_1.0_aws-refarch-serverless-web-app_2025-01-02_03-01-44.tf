terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

# Provider Configuration
provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "project_name" {
  type    = string
  default = "todo-list"
}

variable "environment" {
  type    = string
  default = "prod"
}

# Networking
# (No explicit networking resources needed for serverless architecture)

# Authentication - Amazon Cognito
resource "aws_cognito_user_pool" "todo_user_pool" {
  name = "${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols  = false
    require_numbers  = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_client" "todo_user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.todo_user_pool.id

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"
  explicit_auth_flows                  = ["ALLOW_ADMIN_USER_PASSWORD_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  supported_identity_providers         = ["COGNITO"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_domain" "todo_user_pool_domain" {
  domain       = "${var.stack_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.todo_user_pool.id
}

# Database - DynamoDB
resource "aws_dynamodb_table" "todo_table" {
  name             = "todo-table-${var.stack_name}"
  billing_mode     = "PROVISIONED"
  read_capacity    = 5
  write_capacity   = 5
  hash_key         = "cognito-username"
  range_key        = "id"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

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
    Project     = var.project_name
    Environment = var.environment
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name} application"
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_method_settings" "todo_api_settings" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = aws_api_gateway_deployment.todo_api_deployment.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name          = "${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_user_pool.arn]
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name} API"

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
}

resource "aws_api_gateway_cors_configuration" "todo_cors_config" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id

  allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  allow_headers = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
  allow_origins = ["*"]
}

# Lambda Functions
resource "aws_lambda_function" "todo_lambda_add_item" {
  function_name    = "${var.stack_name}-add-item"
  filename         = "lambda_functions/add_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/add_item.zip")
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_lambda_function" "todo_lambda_get_item" {
  function_name    = "${var.stack_name}-get-item"
  filename         = "lambda_functions/get_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/get_item.zip")
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-get-item"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_lambda_function" "todo_lambda_get_all_items" {
  function_name    = "${var.stack_name}-get-all-items"
  filename         = "lambda_functions/get_all_items.zip"
  source_code_hash = filebase64sha256("lambda_functions/get_all_items.zip")
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_lambda_function" "todo_lambda_update_item" {
  function_name    = "${var.stack_name}-update-item"
  filename         = "lambda_functions/update_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/update_item.zip")
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-update-item"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_lambda_function" "todo_lambda_complete_item" {
  function_name    = "${var.stack_name}-complete-item"
  filename         = "lambda_functions/complete_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/complete_item.zip")
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-complete-item"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_lambda_function" "todo_lambda_delete_item" {
  function_name    = "${var.stack_name}-delete-item"
  filename         = "lambda_functions/delete_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/delete_item.zip")
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-delete-item"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Amplify
resource "aws_amplify_app" "todo_app" {
  name       = "${var.stack_name}-frontend"
  repository = "https://github.com/your-repo/todo-frontend"

  build_spec = <<-EOT
    version: 0.1
    frontend:
      phases:
        build:
          commands:
            - npm ci
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
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_amplify_branch" "todo_app_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"

  framework = "React"
  stage     = "PRODUCTION"

  environment_variables = {
    AMPLIFY_MONOREPO_APP_ROOT = "frontend"
  }

  tags = {
    Name        = "${var.stack_name}-frontend-branch"
    Project     = var.project_name
    Environment = var.environment
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "apigateway_role" {
  name = "${var.stack_name}-apigateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-apigateway-role"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "apigateway_policy" {
  name = "${var.stack_name}-apigateway-policy"
  role = aws_iam_role.apigateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/api-gateway/*"
      },
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
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "amplify:*"
        Effect   = "Allow"
        Resource = "*"
      },
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
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-role"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.stack_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      },
      {
        Action   = "cloudwatch:PutMetricData"
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# CloudWatch Logs and Alarms
resource "aws_cloudwatch_log_group" "todo_api_log_group" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.todo_api.name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-api-log-group"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each          = toset([
    aws_lambda_function.todo_lambda_add_item.function_name,
    aws_lambda_function.todo_lambda_get_item.function_name,
    aws_lambda_function.todo_lambda_get_all_items.function_name,
    aws_lambda_function.todo_lambda_update_item.function_name,
    aws_lambda_function.todo_lambda_complete_item.function_name,
    aws_lambda_function.todo_lambda_delete_item.function_name
  ])
  name              = "/aws/lambda/${each.value}"
  retention_in_days = 30

  tags = {
    Name        = "${each.value}-log-group"
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  for_each            = toset([
    aws_lambda_function.todo_lambda_add_item.function_name,
    aws_lambda_function.todo_lambda_get_item.function_name,
    aws_lambda_function.todo_lambda_get_all_items.function_name,
    aws_lambda_function.todo_lambda_update_item.function_name,
    aws_lambda_function.todo_lambda_complete_item.function_name,
    aws_lambda_function.todo_lambda_delete_item.function_name
  ])
  alarm_name          = "${each.value}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${each.value}"
  alarm_actions       = [aws_sns_topic.lambda_error_sns_topic.arn]

  dimensions = {
    FunctionName = each.value
  }
}

resource "aws_sns_topic" "lambda_error_sns_topic" {
  name = "${var.stack_name}-lambda-error-topic"

  tags = {
    Name        = "${var.stack_name}-lambda-error-topic"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Data Sources
data "aws_caller_identity" "current" {}

# Outputs
output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_api_deployment.invoke_url
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_user_pool_client.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.todo_user_pool_domain.domain
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_id" {
  value = aws_amplify_branch.todo_app_branch.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}
