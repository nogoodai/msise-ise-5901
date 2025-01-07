terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "app_name" {
  description = "Application name"
  default     = "todo-app"
}

variable "stack_name" {
  description = "Stack name"
  default     = "prod"
}

variable "github_repo_url" {
  description = "GitHub repository URL for Amplify"
  default     = "https://github.com/your-org/your-repo"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito custom domain"
  default     = "auth"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.app_name}-${var.stack_name}-user-pool"

  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.app_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                  = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.app_name}-${var.stack_name}"
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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.app_name}-${var.stack_name}-api"
  description = "REST API for ${var.app_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.app_name}-${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_method_settings" "api_gateway_settings" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = aws_api_gateway_deployment.api_deployment.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.app_name}-${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.app_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
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
resource "aws_lambda_function" "add_item" {
  filename         = "lambda_functions/add_item.zip"
  function_name    = "${var.app_name}-${var.stack_name}-add-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/add_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename         = "lambda_functions/get_item.zip"
  function_name    = "${var.app_name}-${var.stack_name}-get-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/get_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-get-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename         = "lambda_functions/get_all_items.zip"
  function_name    = "${var.app_name}-${var.stack_name}-get-all-items"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/get_all_items.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-get-all-items"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename         = "lambda_functions/update_item.zip"
  function_name    = "${var.app_name}-${var.stack_name}-update-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/update_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-update-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename         = "lambda_functions/complete_item.zip"
  function_name    = "${var.app_name}-${var.stack_name}-complete-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/complete_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-complete-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename         = "lambda_functions/delete_item.zip"
  function_name    = "${var.app_name}-${var.stack_name}-delete-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/delete_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-delete-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Amplify App
resource "aws_amplify_app" "app" {
  name       = "${var.app_name}-${var.stack_name}"
  repository = var.github_repo_url

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
    EOT

  tags = {
    Name        = "${var.app_name}-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.app.id
  branch_name = "master"

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-master-branch"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# IAM Roles and Policies
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
    Name        = "${var.app_name}-${var.stack_name}-api-gateway-role"
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
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/api-gateway/*"
      },
      {
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/api-gateway/*:*"
      }
    ]
  })
}

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
    Name        = "${var.app_name}-${var.stack_name}-amplify-role"
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
        Action   = [
          "amplify:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

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
    Name        = "${var.app_name}-${var.stack_name}-lambda-role"
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
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action   = [
          "cloudwatch:PutMetricData"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.app_name}-${var.stack_name}-lambda-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda function errors for ${var.app_name}"
  alarm_actions       = [aws_sns_topic.lambda_error_topic.arn]

  dimensions = {
    FunctionName = aws_lambda_function.add_item.function_name
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-lambda-error-alarm"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# SNS Topic for Lambda Error Alarms
resource "aws_sns_topic" "lambda_error_topic" {
  name = "${var.app_name}-${var.stack_name}-lambda-error-topic"

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-lambda-error-topic"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "Cognito User Pool ID"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.user_pool_client.id
  description = "Cognito User Pool Client ID"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.user_pool_domain.domain
  description = "Cognito Domain"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "DynamoDB Table Name"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.api_gateway.id
  description = "API Gateway ID"
}

output "api_gateway_url" {
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
  description = "API Gateway URL"
}

output "lambda_functions_arns" {
  value = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn
  ]
  description = "ARNs of Lambda Functions"
}

output "amplify_app_id" {
  value       = aws_amplify_app.app.id
  description = "Amplify App ID"
}

output "amplify_branch_name" {
  value       = aws_amplify_branch.master.branch_name
  description = "Amplify Branch Name"
}
