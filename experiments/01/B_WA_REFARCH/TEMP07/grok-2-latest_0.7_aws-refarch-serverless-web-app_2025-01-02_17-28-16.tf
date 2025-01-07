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
  description = "The name of the stack for resource naming"
  default     = "todo-app"
}

variable "domain_name" {
  description = "The custom domain name for the Cognito user pool"
  default     = "auth.example.com"
}

variable "github_repo" {
  description = "GitHub repository for Amplify app"
  default     = "user/todo-frontend"
}

variable "github_token" {
  description = "GitHub personal access token for Amplify app"
  default     = "ghp_1234567890abcdef"
}

# Provider
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_user_pool" {
  name = "${var.stack_name}-user-pool"

  username_attributes      = ["email"]
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
    Project     = "todo-app"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.todo_user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                  = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "todo_user_pool_domain" {
  domain       = var.domain_name
  user_pool_id = aws_cognito_user_pool.todo_user_pool.id
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
    Environment = "production"
    Project     = "todo-app"
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
    Environment = "production"
    Project     = "todo-app"
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
  name        = "${var.stack_name}-api-usage-plan"
  description = "Usage plan for Todo App API"

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
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_authorizer" "todo_api_authorizer" {
  name                   = "${var.stack_name}-api-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.todo_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.todo_user_pool.arn]
  authorizer_credentials = aws_iam_role.api_gateway_role.arn
}

# Lambda Functions
resource "aws_lambda_function" "todo_lambda" {
  for_each = toset(["add", "get", "getAll", "update", "complete", "delete"])

  function_name = "${var.stack_name}-${each.key}-item"
  filename      = "lambda_function_payload.zip"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-${each.key}-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "todo_api_integration" {
  for_each = aws_lambda_function.todo_lambda

  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.todo_api_resource[each.key].id
  http_method             = aws_api_gateway_method.todo_api_method[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = each.value.invoke_arn
}

# Amplify App
resource "aws_amplify_app" "todo_frontend" {
  name       = "${var.stack_name}-frontend"
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
    Name        = "${var.stack_name}-frontend"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_amplify_branch" "todo_frontend_master" {
  app_id      = aws_amplify_app.todo_frontend.id
  branch_name = "master"

  enable_auto_build = true

  tags = {
    Name        = "${var.stack_name}-frontend-master"
    Environment = "production"
    Project     = "todo-app"
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
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.stack_name}-api-gateway-policy"
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
    Project     = "todo-app"
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
    Project     = "todo-app"
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/*:*"
      },
      {
        Action   = "xray:PutTraceSegments"
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Logs and Alarms
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.todo_api.name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-api-gateway-logs"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  alarm_name          = "${var.stack_name}-api-gateway-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors 5XX errors in API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.todo_api.name
    Stage   = aws_api_gateway_deployment.todo_api_deployment.stage_name
  }

  tags = {
    Name        = "${var.stack_name}-api-gateway-5xx-errors-alarm"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = aws_lambda_function.todo_lambda

  name              = "/aws/lambda/${each.value.function_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-${each.key}-lambda-logs"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = aws_lambda_function.todo_lambda

  alarm_name          = "${var.stack_name}-${each.key}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors errors in Lambda function ${each.value.function_name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${var.stack_name}-${each.key}-lambda-errors-alarm"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_user_pool_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.todo_user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_api_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_frontend.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.todo_frontend.default_domain
}
