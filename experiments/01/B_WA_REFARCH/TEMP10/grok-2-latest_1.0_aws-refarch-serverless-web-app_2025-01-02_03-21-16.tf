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
  description = "Name of the stack"
  default     = "todo-app"
}

variable "github_repo" {
  description = "GitHub repository URL for the Amplify app"
  default     = "https://github.com/user/todo-frontend"
}

# Provider
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                     = "${var.stack_name}-user-pool"
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
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  allowed_oauth_flows = [
    "code",
    "implicit"
  ]

  allowed_oauth_scopes = [
    "email",
    "phone",
    "openid"
  ]

  generate_secret = false

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
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
    Environment = "production"
    Project     = "todo-app"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for Todo Application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name} API"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod_stage.stage_name
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
  function_name = "${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/add_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/add_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.stack_name}-get-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/get_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/get_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.stack_name}-get-all-items"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/get_all_items.zip"
  source_code_hash = filebase64sha256("lambda_functions/get_all_items.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.stack_name}-update-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/update_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/update_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.stack_name}-complete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/complete_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/complete_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-complete-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.stack_name}-delete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/delete_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/delete_item.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
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

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.stack_name}-frontend-master"
    Environment = "production"
    Project     = "todo-app"
  }
}

# IAM Roles and Policies
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

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
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
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

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

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
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
        Effect = "Allow"
        Action = [
          "amplify:*"
        ]
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
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_errors" {
  alarm_name          = "${var.stack_name}-api-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This alarm monitors 4XX errors on the API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.api.name
  }

  tags = {
    Name        = "${var.stack_name}-api-4xx-errors-alarm"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.stack_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This alarm monitors errors on Lambda functions"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.add_item.function_name
  }

  tags = {
    Name        = "${var.stack_name}-lambda-errors-alarm"
    Environment = "production"
    Project     = "todo-app"
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

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.prod_stage.invoke_url
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

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_app_url" {
  value = aws_amplify_app.todo_app.default_domain
}
