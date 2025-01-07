terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "Stack name for resource naming"
}

variable "cognito_domain_prefix" {
  type        = string
  default     = "todo-app-auth"
  description = "Custom domain prefix for Cognito User Pool"
}

variable "github_repo" {
  type        = string
  default     = "user/todo-app-frontend"
  description = "GitHub repository for Amplify app"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment tag for resources"
}

variable "project" {
  type        = string
  default     = "todo-app"
  description = "Project tag for resources"
}

# Provider
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.project
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_deployment.main.stage_name
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
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  filename      = "lambda_functions/add_item.zip"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.stack_name}-get-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  filename      = "lambda_functions/get_item.zip"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.stack_name}-get-all-items"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  filename      = "lambda_functions/get_all_items.zip"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.stack_name}-update-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  filename      = "lambda_functions/update_item.zip"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.stack_name}-complete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  filename      = "lambda_functions/complete_item.zip"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-complete-item"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.stack_name}-delete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  filename      = "lambda_functions/delete_item.zip"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = var.environment
    Project     = var.project
  }
}

# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.stack_name}-frontend"
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
    EOT

  environment_variables = {
    ENV = var.environment
  }

  tags = {
    Name        = "${var.stack_name}-frontend"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
  framework   = "React"

  tags = {
    Name        = "${var.stack_name}-frontend-branch"
    Environment = var.environment
    Project     = var.project
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
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_role.id

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
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
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
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.stack_name}-lambda-cloudwatch-policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/*"
      }
    ]
  })
}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.main.name}"

  tags = {
    Name        = "${aws_api_gateway_rest_api.main.name}-log-group"
    Environment = var.environment
    Project     = var.project
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
  threshold           = "1"
  alarm_description   = "This metric monitors 5XX errors for API Gateway"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.main.name
  }

  tags = {
    Name        = "${var.stack_name}-api-gateway-5xx-errors-alarm"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  count = 6
  name  = "/aws/lambda/${element([aws_lambda_function.add_item.function_name, aws_lambda_function.get_item.function_name, aws_lambda_function.get_all_items.function_name, aws_lambda_function.update_item.function_name, aws_lambda_function.complete_item.function_name, aws_lambda_function.delete_item.function_name], count.index)}"

  tags = {
    Name        = "${element([aws_lambda_function.add_item.function_name, aws_lambda_function.get_item.function_name, aws_lambda_function.get_all_items.function_name, aws_lambda_function.update_item.function_name, aws_lambda_function.complete_item.function_name, aws_lambda_function.delete_item.function_name], count.index)}-log-group"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = 6
  alarm_name          = "${element([aws_lambda_function.add_item.function_name, aws_lambda_function.get_item.function_name, aws_lambda_function.get_all_items.function_name, aws_lambda_function.update_item.function_name, aws_lambda_function.complete_item.function_name, aws_lambda_function.delete_item.function_name], count.index)}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors errors for Lambda function ${element([aws_lambda_function.add_item.function_name, aws_lambda_function.get_item.function_name, aws_lambda_function.get_all_items.function_name, aws_lambda_function.update_item.function_name, aws_lambda_function.complete_item.function_name, aws_lambda_function.delete_item.function_name], count.index)}"

  dimensions = {
    FunctionName = element([aws_lambda_function.add_item.function_name, aws_lambda_function.get_item.function_name, aws_lambda_function.get_all_items.function_name, aws_lambda_function.update_item.function_name, aws_lambda_function.complete_item.function_name, aws_lambda_function.delete_item.function_name], count.index)
  }

  tags = {
    Name        = "${element([aws_lambda_function.add_item.function_name, aws_lambda_function.get_item.function_name, aws_lambda_function.get_all_items.function_name, aws_lambda_function.update_item.function_name, aws_lambda_function.complete_item.function_name, aws_lambda_function.delete_item.function_name], count.index)}-errors-alarm"
    Environment = var.environment
    Project     = var.project
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

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.main.default_domain
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn,
  ]
}
