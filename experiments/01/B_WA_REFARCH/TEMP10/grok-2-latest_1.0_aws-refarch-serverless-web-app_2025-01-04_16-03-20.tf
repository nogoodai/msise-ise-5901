terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Name of the stack"
  type        = string
  default     = "todo-app"
}

variable "application_name" {
  description = "Name of the application"
  type        = string
  default     = "todo-app"
}

variable "github_repo" {
  description = "GitHub repository URL for frontend"
  type        = string
  default     = "https://github.com/user/todo-frontend"
}

variable "github_branch" {
  description = "GitHub branch to use for frontend"
  type        = string
  default     = "master"
}

# Provider configuration
provider "aws" {
  region = var.aws_region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
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

  generate_secret = false

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["https://${var.stack_name}-user-pool-domain.auth.${var.aws_region}.amazoncognito.com/login"]
  logout_urls                          = ["https://${var.stack_name}-user-pool-domain.auth.${var.aws_region}.amazoncognito.com/logout"]
  supported_identity_providers         = ["COGNITO"]
  prevent_user_existence_errors        = "ENABLED"
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-user-pool-domain"
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
resource "aws_api_gateway_rest_api" "api" {
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

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.application_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
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
  name                   = "${var.stack_name}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

# Lambda Functions
resource "aws_lambda_function" "lambda_functions" {
  for_each = {
    "add-item"      = { function_name = "AddItemFunction", handler = "addItem.handler" }
    "get-item"      = { function_name = "GetItemFunction", handler = "getItem.handler" }
    "get-all-items" = { function_name = "GetAllItemsFunction", handler = "getAllItems.handler" }
    "update-item"   = { function_name = "UpdateItemFunction", handler = "updateItem.handler" }
    "complete-item" = { function_name = "CompleteItemFunction", handler = "completeItem.handler" }
    "delete-item"   = { function_name = "DeleteItemFunction", handler = "deleteItem.handler" }
  }

  function_name = "${var.stack_name}-${each.value.function_name}"
  filename      = "lambda.zip"
  handler       = each.value.handler
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_role.arn

  tags = {
    Name        = "${var.stack_name}-${each.value.function_name}"
    Environment = "prod"
    Project     = var.application_name
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }
}

# Lambda Permissions
resource "aws_lambda_permission" "apigw_lambda" {
  for_each      = aws_lambda_function.lambda_functions
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "lambda_integrations" {
  for_each       = aws_lambda_function.lambda_functions
  rest_api_id    = aws_api_gateway_rest_api.api.id
  resource_id    = aws_api_gateway_resource.resources["root"].id
  http_method    = aws_api_gateway_method.methods["root-${each.key}"].http_method
  integration_http_method = "POST"
  type           = "AWS_PROXY"
  uri            = each.value.invoke_arn
}

# API Gateway Resources and Methods
resource "aws_api_gateway_resource" "resources" {
  for_each    = {
    "root" = { parent_id = null, path_part = null }
    "item" = { parent_id = aws_api_gateway_resource.resources["root"].id, path_part = "item" }
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = each.value.parent_id == null ? "" : each.value.parent_id
  path_part   = each.value.path_part == null ? "" : each.value.path_part
}

resource "aws_api_gateway_method" "methods" {
  for_each      = {
    "root-add-item"      = { resource_id = aws_api_gateway_resource.resources["root"].id, http_method = "POST", authorization = "COGNITO_USER_POOLS" }
    "root-get-item"      = { resource_id = aws_api_gateway_resource.resources["root"].id, http_method = "GET", authorization = "COGNITO_USER_POOLS" }
    "root-get-all-items" = { resource_id = aws_api_gateway_resource.resources["root"].id, http_method = "GET", authorization = "COGNITO_USER_POOLS" }
    "item-update-item"   = { resource_id = aws_api_gateway_resource.resources["item"].id, http_method = "PUT", authorization = "COGNITO_USER_POOLS" }
    "item-complete-item" = { resource_id = aws_api_gateway_resource.resources["item"].id, http_method = "POST", authorization = "COGNITO_USER_POOLS" }
    "item-delete-item"   = { resource_id = aws_api_gateway_resource.resources["item"].id, http_method = "DELETE", authorization = "COGNITO_USER_POOLS" }
  }

  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = each.value.resource_id
  http_method   = each.value.http_method
  authorization = each.value.authorization
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = each.value.http_method == "GET" ? {
    "method.request.path.id" = true
  } : {}
}

# Amplify App
resource "aws_amplify_app" "frontend" {
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
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = var.github_branch

  framework = "React"
  enable_auto_build = true

  tags = {
    Name        = "${var.stack_name}-frontend-branch"
    Environment = "prod"
    Project     = var.application_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "apigateway_role" {
  name = "${var.stack_name}-apigateway-role"

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
    Name        = "${var.stack_name}-apigateway-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "apigateway_policy" {
  name = "${var.stack_name}-apigateway-policy"
  role = aws_iam_role.apigateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/apigateway/*"
      },
      {
        Action   = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/apigateway/*:log-stream:*"
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
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
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

resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.stack_name}-lambda-cloudwatch-policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/*:*"
      }
    ]
  })
}

# CloudWatch Logs and Alarms
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/apigateway/${aws_api_gateway_rest_api.api.name}"

  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-api-gateway-log-group"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  for_each = aws_lambda_function.lambda_functions

  alarm_name          = "${var.stack_name}-${each.key}-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${each.key}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${var.stack_name}-${each.key}-error-alarm"
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

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}

output "amplify_app_default_domain" {
  value = aws_amplify_app.frontend.default_domain
}
