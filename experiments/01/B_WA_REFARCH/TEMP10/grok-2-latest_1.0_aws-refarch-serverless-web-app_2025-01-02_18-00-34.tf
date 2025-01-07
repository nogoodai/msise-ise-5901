terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Provider configuration
provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name used for resource naming"
  default     = "todo-app"
}

variable "stack_name" {
  description = "Stack name used for resource naming"
  default     = "prod"
}

variable "github_repo" {
  description = "GitHub repository for the Amplify app"
  default     = "owner/todo-app"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.app_name}-${var.stack_name}-user-pool"

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
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${aws_amplify_app.frontend_app.default_domain}"]
  logout_urls                          = ["https://${aws_amplify_app.frontend_app.default_domain}"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  enable_propagate_additional_user_context_data = true

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.app_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name             = "todo-table-${var.stack_name}"
  billing_mode     = "PROVISIONED"
  read_capacity    = 5
  write_capacity   = 5
  hash_key         = "cognito-username"
  range_key        = "id"

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
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.app_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.app_name} application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "todo_api_usage_plan" {
  name        = "${var.app_name}-${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.app_name} API"

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
    Name        = "${var.app_name}-${var.stack_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# API Gateway Cognito Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.app_name}-${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.app_name}-${var.stack_name}-add-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_add_item.zip"
  source_code_hash = filebase64sha256("lambda_add_item.zip")

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

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
  function_name = "${var.app_name}-${var.stack_name}-get-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_get_item.zip"
  source_code_hash = filebase64sha256("lambda_get_item.zip")

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

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
  function_name = "${var.app_name}-${var.stack_name}-get-all-items"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_get_all_items.zip"
  source_code_hash = filebase64sha256("lambda_get_all_items.zip")

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

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
  function_name = "${var.app_name}-${var.stack_name}-update-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_update_item.zip"
  source_code_hash = filebase64sha256("lambda_update_item.zip")

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

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
  function_name = "${var.app_name}-${var.stack_name}-complete-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_complete_item.zip"
  source_code_hash = filebase64sha256("lambda_complete_item.zip")

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

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
  function_name = "${var.app_name}-${var.stack_name}-delete-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_delete_item.zip"
  source_code_hash = filebase64sha256("lambda_delete_item.zip")

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

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
resource "aws_amplify_app" "frontend_app" {
  name       = "${var.app_name}-${var.stack_name}-frontend"
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
    Name        = "${var.app_name}-${var.stack_name}-frontend"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.frontend_app.id
  branch_name = "master"
  framework   = "React"
  stage       = "PRODUCTION"

  environment_variables = {
    ENV = var.stack_name
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-master-branch"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "apigateway_role" {
  name = "${var.app_name}-${var.stack_name}-apigateway-role"

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
    Name        = "${var.app_name}-${var.stack_name}-apigateway-role"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_iam_policy" "apigateway_cloudwatch_policy" {
  name        = "${var.app_name}-${var.stack_name}-apigateway-cloudwatch-policy"
  path        = "/"
  description = "Allow API Gateway to write logs to CloudWatch"

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
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/api-gateway/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apigateway_cloudwatch" {
  role       = aws_iam_role.apigateway_role.name
  policy_arn = aws_iam_policy.apigateway_cloudwatch_policy.arn
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

resource "aws_iam_policy" "amplify_manage_resources_policy" {
  name        = "${var.app_name}-${var.stack_name}-amplify-manage-resources-policy"
  path        = "/"
  description = "Allow Amplify to manage resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::${aws_amplify_app.frontend_app.arn}",
          "arn:aws:s3:::${aws_amplify_app.frontend_app.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_manage_resources" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_manage_resources_policy.arn
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

resource "aws_iam_policy" "lambda_dynamodb_crud_policy" {
  name        = "${var.app_name}-${var.stack_name}-lambda-dynamodb-crud-policy"
  path        = "/"
  description = "Allow Lambda to perform CRUD operations on DynamoDB"

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
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_read_policy" {
  name        = "${var.app_name}-${var.stack_name}-lambda-dynamodb-read-policy"
  path        = "/"
  description = "Allow Lambda to perform read operations on DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_cloudwatch_metrics_policy" {
  name        = "${var.app_name}-${var.stack_name}-lambda-cloudwatch-metrics-policy"
  path        = "/"
  description = "Allow Lambda to publish metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_crud" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_crud_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_read" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_read_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_metrics" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_metrics_policy.arn
}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.todo_api.name}"
  retention_in_days = 30

  tags = {
    Name        = "${aws_api_gateway_rest_api.todo_api.name}-logs"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.app_name}-${var.stack_name}-lambda-error-alarm"
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
    FunctionName = aws_lambda_function.add_item.function_name
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-lambda-error-alarm"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_latency_alarm" {
  alarm_name          = "${var.app_name}-${var.stack_name}-api-gateway-latency-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Average"
  threshold           = "1000" # 1 second
  alarm_description   = "This metric monitors API Gateway latency"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.todo_api.name
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-api-gateway-latency-alarm"
    Environment = var.stack_name
    Project     = var.app_name
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
  value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_api_deployment.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.frontend_app.default_domain
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn
  ]
}
