terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Networking
variable "vpc_id" {
  description = "The VPC ID for networking resources"
  type        = string
  default     = ""
}

# Compute - Lambda Functions
variable "lambda_runtime" {
  description = "The runtime for Lambda functions"
  type        = string
  default     = "nodejs12.x"
}

variable "lambda_memory" {
  description = "The memory allocation for Lambda functions"
  type        = number
  default     = 1024
}

variable "lambda_timeout" {
  description = "The timeout for Lambda functions"
  type        = number
  default     = 60
}

variable "stack_name" {
  description = "The name of the stack for naming conventions"
  type        = string
  default     = "todo-app"
}

variable "cognito_domain_prefix" {
  description = "The prefix for the custom Cognito domain"
  type        = string
  default     = "auth"
}

variable "api_gateway_stage" {
  description = "The stage name for API Gateway"
  type        = string
  default     = "prod"
}

variable "github_repo" {
  description = "The GitHub repository URL for Amplify"
  type        = string
  default     = "https://github.com/user/repo"
}

variable "amplify_branch_name" {
  description = "The branch name for Amplify app deployment"
  type        = string
  default     = "master"
}

# Provider Configuration
provider "aws" {
  region = "us-east-1"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
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
    Environment = "production"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name = "${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls = ["https://${aws_amplify_app.frontend_app.default_domain}/"]
  logout_urls = ["https://${aws_amplify_app.frontend_app.default_domain}/"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = var.stack_name
  }
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name        = "${var.stack_name}-user-pool-domain"
    Environment = "production"
    Project     = var.stack_name
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
    Environment = "production"
    Project     = var.stack_name
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
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = var.api_gateway_stage

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.todo_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name = "${var.stack_name}-usage-plan"

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
    Name        = "${var.stack_name}-usage-plan"
    Environment = "production"
    Project     = var.stack_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_functions/add_item.zip"
  function_name = "${var.stack_name}-add-item"
  role          = aws_iam_role.lambda_dynamodb_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory
  timeout       = var.lambda_timeout

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_functions/get_item.zip"
  function_name = "${var.stack_name}-get-item"
  role          = aws_iam_role.lambda_dynamodb_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory
  timeout       = var.lambda_timeout

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_functions/get_all_items.zip"
  function_name = "${var.stack_name}-get-all-items"
  role          = aws_iam_role.lambda_dynamodb_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory
  timeout       = var.lambda_timeout

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_functions/update_item.zip"
  function_name = "${var.stack_name}-update-item"
  role          = aws_iam_role.lambda_dynamodb_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory
  timeout       = var.lambda_timeout

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_functions/complete_item.zip"
  function_name = "${var.stack_name}-complete-item"
  role          = aws_iam_role.lambda_dynamodb_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory
  timeout       = var.lambda_timeout

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-complete-item"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_functions/delete_item.zip"
  function_name = "${var.stack_name}-delete-item"
  role          = aws_iam_role.lambda_dynamodb_role.arn
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory
  timeout       = var.lambda_timeout

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = "production"
    Project     = var.stack_name
  }
}

# Amplify App
resource "aws_amplify_app" "frontend_app" {
  name       = "${var.stack_name}-frontend"
  repository = var.github_repo

  build_spec = <<-EOT
    version: 0.1
    frontend:
      phases:
        preBuild:
          commands:
            - npm install
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: build
        files:
          - '**/*'
    EOT

  tags = {
    Name        = "${var.stack_name}-frontend"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.frontend_app.id
  branch_name = var.amplify_branch_name
  framework   = "React"
  stage       = "PRODUCTION"

  environment_variables = {
    API_URL = aws_api_gateway_deployment.todo_api_deployment.invoke_url
  }

  tags = {
    Name        = "${var.stack_name}-frontend-master"
    Environment = "production"
    Project     = var.stack_name
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
    Project     = var.stack_name
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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:log-group:/aws/api-gateway/*"
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
    Project     = var.stack_name
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

resource "aws_iam_role" "lambda_dynamodb_role" {
  name = "${var.stack_name}-lambda-dynamodb-role"

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
    Name        = "${var.stack_name}-lambda-dynamodb-role"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_dynamodb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
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
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.todo_api.name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-api-gateway-log-group"
    Environment = "production"
    Project     = var.stack_name
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
  alarm_description   = "This metric monitors 5XX errors from API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.todo_api.name
    Stage   = var.api_gateway_stage
  }

  tags = {
    Name        = "${var.stack_name}-api-gateway-5xx-errors"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  count = 6

  name              = "/aws/lambda/${element([aws_lambda_function.add_item.function_name, aws_lambda_function.get_item.function_name, aws_lambda_function.get_all_items.function_name, aws_lambda_function.update_item.function_name, aws_lambda_function.complete_item.function_name, aws_lambda_function.delete_item.function_name], count.index)}"
  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-lambda-log-group-${count.index}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = 6

  alarm_name          = "${var.stack_name}-lambda-errors-${element(["add", "get", "get-all", "update", "complete", "delete"], count.index)}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors errors from Lambda function"
  alarm_actions       = []

  dimensions = {
    FunctionName = element([aws_lambda_function.add_item.function_name, aws_lambda_function.get_item.function_name, aws_lambda_function.get_all_items.function_name, aws_lambda_function.update_item.function_name, aws_lambda_function.complete_item.function_name, aws_lambda_function.delete_item.function_name], count.index)
  }

  tags = {
    Name        = "${var.stack_name}-lambda-errors-${element(["add", "get", "get-all", "update", "complete", "delete"], count.index)}"
    Environment = "production"
    Project     = var.stack_name
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
  value = aws_api_gateway_deployment.todo_api_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend_app.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.frontend_app.default_domain
}
