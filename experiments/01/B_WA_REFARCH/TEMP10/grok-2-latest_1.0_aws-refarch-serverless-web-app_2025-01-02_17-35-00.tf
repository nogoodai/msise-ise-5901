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

variable "application_name" {
  description = "Name of the application"
  default     = "todo-app"
}

variable "github_repo" {
  description = "GitHub repository for the frontend"
  default     = "owner/todo-frontend"
}

# Provider Configuration
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers = false
    require_symbols = false
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_client" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.todo_pool.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${var.application_name}.${var.stack_name}.com"]
  logout_urls                          = ["https://${var.application_name}.${var.stack_name}.com"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "todo_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_pool.id
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
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name        = "${var.application_name}-${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.application_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
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
    Name        = "${var.application_name}-${var.stack_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "todo_functions" {
  for_each = {
    add_item     = { method = "POST", path = "/item" }
    get_item     = { method = "GET", path = "/item/{id}" }
    get_all_items = { method = "GET", path = "/item" }
    update_item  = { method = "PUT", path = "/item/{id}" }
    complete_item = { method = "POST", path = "/item/{id}/done" }
    delete_item  = { method = "DELETE", path = "/item/{id}" }
  }

  function_name    = "${var.application_name}-${var.stack_name}-${each.key}"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  role             = aws_iam_role.lambda_role.arn

  memory_size = 1024
  timeout     = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-${each.key}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway Lambda Integration
resource "aws_api_gateway_integration" "todo_integration" {
  for_each       = aws_lambda_function.todo_functions
  rest_api_id    = aws_api_gateway_rest_api.todo_api.id
  resource_id    = aws_api_gateway_resource.todo_resource[each.key].id
  http_method    = aws_api_gateway_method.todo_method[each.key].http_method
  integration_http_method = "POST"
  type           = "AWS_PROXY"
  uri            = each.value.invoke_arn
}

# API Gateway Method
resource "aws_api_gateway_method" "todo_method" {
  for_each      = aws_lambda_function.todo_functions
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.todo_resource[each.key].id
  http_method   = each.value.tags.Name
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

# API Gateway Resource
resource "aws_api_gateway_resource" "todo_resource" {
  for_each    = aws_lambda_function.todo_functions
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = each.value.tags.Name
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name          = "${var.application_name}-${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_pool.arn]
}

# Amplify App
resource "aws_amplify_app" "todo_amplify" {
  name       = "${var.application_name}-${var.stack_name}"
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

  enable_branch_auto_build = true

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_amplify.id
  branch_name = "master"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-branch-master"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Roles and Policies
# Lambda Role
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-role"

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
    Name        = "${var.application_name}-${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.application_name}-${var.stack_name}-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# API Gateway Role
resource "aws_iam_role" "apigateway_role" {
  name = "${var.application_name}-${var.stack_name}-apigateway-role"

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
    Name        = "${var.application_name}-${var.stack_name}-apigateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "apigateway_policy" {
  name = "${var.application_name}-${var.stack_name}-apigateway-policy"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-apigateway-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "apigateway_policy_attach" {
  role       = aws_iam_role.apigateway_role.name
  policy_arn = aws_iam_policy.apigateway_policy.arn
}

# Amplify Role
resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-${var.stack_name}-amplify-role"

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
    Name        = "${var.application_name}-${var.stack_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name = "${var.application_name}-${var.stack_name}-amplify-policy"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# CloudWatch Logs for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = aws_lambda_function.todo_functions

  name              = "/aws/lambda/${each.value.function_name}"
  retention_in_days = 14

  tags = {
    Name        = "/aws/lambda/${each.value.function_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# CloudWatch Alarms for Lambda
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = aws_lambda_function.todo_functions

  alarm_name          = "${each.value.function_name}-Errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${each.value.function_name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${each.value.function_name}-Errors"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.todo_pool.id
  description = "Cognito User Pool ID"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.todo_client.id
  description = "Cognito User Pool Client ID"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.todo_domain.domain
  description = "Cognito Custom Domain"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "DynamoDB Table Name"
}

output "api_gateway_url" {
  value       = aws_api_gateway_deployment.todo_deployment.invoke_url
  description = "API Gateway URL"
}

output "amplify_app_id" {
  value       = aws_amplify_app.todo_amplify.id
  description = "Amplify App ID"
}

output "amplify_default_domain" {
  value       = aws_amplify_app.todo_amplify.default_domain
  description = "Amplify Default Domain"
}
