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

variable "project_name" {
  description = "The name of the project"
  default     = "todo-app"
}

variable "environment" {
  description = "The environment (e.g., dev, prod)"
  default     = "prod"
}

variable "cognito_custom_domain" {
  description = "Custom domain for Cognito"
  default     = "auth.todo-app.com"
}

variable "github_repo" {
  description = "GitHub repository for Amplify app"
  default     = "myorg/todo-app-frontend"
}

# Provider
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.environment}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.project_name}-${var.environment}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  generate_secret                      = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = var.cognito_custom_domain
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.environment}"
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
    Name        = "todo-table-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.project_name}-${var.environment}-api"
  description = "Todo Application API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name         = "${var.project_name}-${var.environment}-usage-plan"
  description  = "Usage plan for ${var.project_name} ${var.environment}"
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

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.project_name}-${var.environment}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.todo_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
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

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-${var.environment}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_dynamodb_write_role.arn

  filename      = "lambda_functions/add_item.zip"

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-add-item"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.project_name}-${var.environment}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_dynamodb_read_role.arn

  filename      = "lambda_functions/get_item.zip"

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-get-item"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.project_name}-${var.environment}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_dynamodb_read_role.arn

  filename      = "lambda_functions/get_all_items.zip"

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-get-all-items"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.project_name}-${var.environment}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_dynamodb_write_role.arn

  filename      = "lambda_functions/update_item.zip"

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-update-item"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.project_name}-${var.environment}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_dynamodb_write_role.arn

  filename      = "lambda_functions/complete_item.zip"

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-complete-item"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.project_name}-${var.environment}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_dynamodb_write_role.arn

  filename      = "lambda_functions/delete_item.zip"

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-delete-item"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Amplify App
resource "aws_amplify_app" "todo_frontend" {
  name       = "${var.project_name}-${var.environment}-frontend"
  repository = var.github_repo

  build_spec = <<-EOT
    version: 1
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
    Name        = "${var.project_name}-${var.environment}-frontend"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_frontend.id
  branch_name = "master"

  tags = {
    Name        = "${var.project_name}-${var.environment}-frontend-master"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Roles and Policies
# API Gateway Role
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.project_name}-${var.environment}-api-gateway-cloudwatch-role"

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
    Name        = "${var.project_name}-${var.environment}-api-gateway-cloudwatch-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name   = "${var.project_name}-${var.environment}-api-gateway-cloudwatch-policy"
  role   = aws_iam_role.api_gateway_cloudwatch_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Amplify Role
resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-${var.environment}-amplify-role"

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
    Name        = "${var.project_name}-${var.environment}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name   = "${var.project_name}-${var.environment}-amplify-policy"
  role   = aws_iam_role.amplify_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*",
          "cloudfront:*",
          "route53:*",
          "acm:*",
          "iam:GetRole",
          "iam:PassRole"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Lambda Role for DynamoDB Write
resource "aws_iam_role" "lambda_dynamodb_write_role" {
  name = "${var.project_name}-${var.environment}-lambda-dynamodb-write-role"

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
    Name        = "${var.project_name}-${var.environment}-lambda-dynamodb-write-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_write_policy" {
  name   = "${var.project_name}-${var.environment}-lambda-dynamodb-write-policy"
  role   = aws_iam_role.lambda_dynamodb_write_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Role for DynamoDB Read
resource "aws_iam_role" "lambda_dynamodb_read_role" {
  name = "${var.project_name}-${var.environment}-lambda-dynamodb-read-role"

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
    Name        = "${var.project_name}-${var.environment}-lambda-dynamodb-read-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_read_policy" {
  name   = "${var.project_name}-${var.environment}-lambda-dynamodb-read-policy"
  role   = aws_iam_role.lambda_dynamodb_read_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This alarm monitors Lambda errors for the ${var.project_name} application"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.add_item.function_name
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-error-alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Outputs
output "cognito_user_pool_arn" {
  value = aws_cognito_user_pool.user_pool.arn
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_api_deployment.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.todo_frontend.default_domain
}
