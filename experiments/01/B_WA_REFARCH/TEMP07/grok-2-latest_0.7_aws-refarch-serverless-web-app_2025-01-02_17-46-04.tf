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

variable "stack_name" {
  description = "Stack name for resource naming"
  default     = "todo-app"
}

variable "application_name" {
  description = "Application name for resource naming"
  default     = "todo-app"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito custom domain"
  default     = "auth"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  default     = "user/repo"
}

variable "github_token" {
  description = "GitHub token for Amplify"
  sensitive   = true
}

# Provider
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true

    string_attribute_constraints {
      min_length = 7
      max_length = 256
    }
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  generate_secret = false

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${var.application_name}.amplifyapp.com"]
  logout_urls                          = ["https://${var.application_name}.amplifyapp.com"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name        = "${var.stack_name}-user-pool-domain"
    Environment = "prod"
    Project     = var.application_name
  }
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
    Environment = "prod"
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log_group.arn
    format          = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId $context.extendedRequestId"
  }

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.stack_name}-api-stage"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.application_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
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
    Name        = "${var.stack_name}-usage-plan"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_method_settings" "api_gateway_method_settings" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = true
  }
}

# Lambda Functions
resource "aws_lambda_function" "lambda_function_add_item" {
  function_name = "${var.stack_name}-add-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "lambda_function_get_item" {
  function_name = "${var.stack_name}-get-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "lambda_function_get_all_items" {
  function_name = "${var.stack_name}-get-all-items"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "lambda_function_update_item" {
  function_name = "${var.stack_name}-update-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "lambda_function_complete_item" {
  function_name = "${var.stack_name}-complete-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-complete-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "lambda_function_delete_item" {
  function_name = "${var.stack_name}-delete-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name       = "${var.stack_name}-app"
  repository = var.github_repo
  access_token = var.github_token

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
    Name        = "${var.stack_name}-app"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.stack_name}-branch-master"
    Environment = "prod"
    Project     = var.application_name
  }
}

# IAM Roles and Policies
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
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.stack_name}-api-gateway-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
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
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
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
    Environment = "prod"
    Project     = var.application_name
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
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
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
      }
    ]
  })
}

# CloudWatch Logs and Alarms
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/api-gateway/${var.stack_name}-api"

  tags = {
    Name        = "${var.stack_name}-api-logs"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_errors" {
  alarm_name          = "${var.stack_name}-api-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = "1"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors API Gateway 4XX errors"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.api_gateway.name
    Stage   = aws_api_gateway_stage.api_stage.stage_name
  }

  tags = {
    Name        = "${var.stack_name}-api-4xx-alarm"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.stack_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.lambda_function_add_item.function_name
  }

  tags = {
    Name        = "${var.stack_name}-lambda-error-alarm"
    Environment = "prod"
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
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}
