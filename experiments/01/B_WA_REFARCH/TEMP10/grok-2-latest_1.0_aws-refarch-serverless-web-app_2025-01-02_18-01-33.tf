terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Provider Configuration
provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "application_name" {
  description = "Name of the application"
  default     = "todo-app"
}

variable "stack_name" {
  description = "Name of the stack"
  default     = "prod"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito domain"
  default     = "auth"
}

variable "github_repo" {
  description = "GitHub repository for the frontend"
  default     = "owner/repo"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.application_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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
    Name        = "todo-table"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name = "${var.application_name}-api-${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway Cognito Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  name        = "${var.application_name}-cognito-authorizer-${var.stack_name}"
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name         = "${var.application_name}-usage-plan-${var.stack_name}"
  description  = "Usage plan for the ${var.application_name} API"
  api_stages   = [{
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
  }]

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.application_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.application_name}-add-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "add_item.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/add_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/add_item.zip")

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
  function_name = "${var.application_name}-get-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "get_item.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/get_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/get_item.zip")

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
  function_name = "${var.application_name}-get-all-items-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "get_all_items.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/get_all_items.zip"
  source_code_hash = filebase64sha256("lambda_functions/get_all_items.zip")

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
  function_name = "${var.application_name}-update-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "update_item.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/update_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/update_item.zip")

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
  function_name = "${var.application_name}-complete-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "complete_item.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/complete_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/complete_item.zip")

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
  function_name = "${var.application_name}-delete-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "delete_item.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename         = "lambda_functions/delete_item.zip"
  source_code_hash = filebase64sha256("lambda_functions/delete_item.zip")

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
  name       = "${var.application_name}-frontend-${var.stack_name}"
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

  tags = {
    Name        = "${var.application_name}-frontend"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify Branch
resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"

  framework = "React"
  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-frontend-master"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role-${var.stack_name}"

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

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.application_name}-api-gateway-policy-${var.stack_name}"
  description = "Policy for API Gateway to log to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/api-gateway/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-amplify-role-${var.stack_name}"

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

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.application_name}-amplify-policy-${var.stack_name}"
  description = "Policy for Amplify to manage resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${aws_amplify_app.amplify_app.default_domain}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-lambda-role-${var.stack_name}"

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

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.application_name}-lambda-dynamodb-policy-${var.stack_name}"
  description = "Policy for Lambda to interact with DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
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

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name        = "${var.application_name}-lambda-cloudwatch-policy-${var.stack_name}"
  description = "Policy for Lambda to publish metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.api_gateway.name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.application_name}-api-gateway-logs"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors_alarm" {
  alarm_name          = "${var.application_name}-lambda-errors-alarm-${var.stack_name}"
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
    Name        = "${var.application_name}-lambda-errors-alarm"
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
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}

# Data Sources
data "aws_caller_identity" "current" {}

