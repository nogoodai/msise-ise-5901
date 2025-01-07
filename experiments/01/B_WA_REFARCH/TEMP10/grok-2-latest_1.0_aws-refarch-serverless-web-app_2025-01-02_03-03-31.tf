terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
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

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito domain"
  type        = string
  default     = "auth"
}

variable "github_repo" {
  description = "GitHub repository for frontend hosting"
  type        = string
  default     = "user/todo-app-frontend"
}

variable "amplify_branch_name" {
  description = "Name of the Amplify branch"
  type        = string
  default     = "master"
}

# Provider
provider "aws" {
  region = var.region
}

# Tags
locals {
  tags = {
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
  }

  tags = local.tags
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.application_name}-${var.stack_name}-client"
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
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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

  tags = local.tags
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.tags
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.application_name}-${var.stack_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api_gateway.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.lambda_integration]
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log_group.arn
    format          = "$context.identity.sourceIp $context.identity.caller $context.identity.user $context.requestTime $context.httpMethod $context.resourcePath $context.protocol $context.status $context.responseLength $context.requestId"
  }

  xray_tracing_enabled = true

  tags = local.tags
}

resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name        = "${var.application_name}-${var.stack_name}-usage-plan"
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

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/api-gateway/${var.application_name}-${var.stack_name}"
  retention_in_days = 30

  tags = local.tags
}

# Lambda Functions
resource "aws_lambda_function" "lambda_functions" {
  for_each = {
    "add_item"     = { name = "AddItem", path = "/item", method = "POST" }
    "get_item"     = { name = "GetItem", path = "/item/{id}", method = "GET" }
    "get_all_items"= { name = "GetAllItems", path = "/item", method = "GET" }
    "update_item"  = { name = "UpdateItem", path = "/item/{id}", method = "PUT" }
    "complete_item"= { name = "CompleteItem", path = "/item/{id}/done", method = "POST" }
    "delete_item"  = { name = "DeleteItem", path = "/item/{id}", method = "DELETE" }
  }

  function_name = "${var.application_name}-${var.stack_name}-${each.value.name}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = local.tags

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  for_each      = aws_lambda_function.lambda_functions
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_api_gateway_resource" "lambda_resource" {
  for_each    = aws_lambda_function.lambda_functions
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = split("/", each.value.environment[0].variables.path)[1]
}

resource "aws_api_gateway_method" "lambda_method" {
  for_each      = aws_lambda_function.lambda_functions
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.lambda_resource[each.key].id
  http_method   = each.value.environment[0].variables.method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.id" = true
  }
}

resource "aws_api_gateway_integration" "lambda_integration" {
  for_each       = aws_lambda_function.lambda_functions
  rest_api_id    = aws_api_gateway_rest_api.api_gateway.id
  resource_id    = aws_api_gateway_resource.lambda_resource[each.key].id
  http_method    = aws_api_gateway_method.lambda_method[each.key].http_method
  integration_http_method = "POST"
  type           = "AWS_PROXY"
  uri            = aws_lambda_function.lambda_functions[each.key].invoke_arn
}

# Amplify App
resource "aws_amplify_app" "frontend_app" {
  name       = "${var.application_name}-${var.stack_name}-frontend"
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
    ENV = var.stack_name
  }

  tags = local.tags
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.frontend_app.id
  branch_name = var.amplify_branch_name
  enable_auto_build = true

  tags = local.tags
}

# IAM Roles and Policies
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

  tags = local.tags
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.application_name}-${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.application_name}-${var.stack_name}-lambda-cloudwatch-policy"
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
  name = "${var.application_name}-${var.stack_name}-api-gateway-role"

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

  tags = local.tags
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cloudwatch-policy"
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

  tags = local.tags
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.application_name}-${var.stack_name}-amplify-policy"
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

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  for_each = aws_lambda_function.lambda_functions

  alarm_name          = "${var.application_name}-${var.stack_name}-${each.key}-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${each.key}"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_latency_alarm" {
  alarm_name          = "${var.application_name}-${var.stack_name}-api-gateway-latency-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Average"
  threshold           = "1000" # Set to 1 second
  alarm_description   = "This metric monitors API Gateway latency"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    ApiName = aws_api_gateway_rest_api.api_gateway.name
    Stage   = aws_api_gateway_stage.api_stage.stage_name
  }

  tags = local.tags
}

# Outputs
output "cognito_user_pool_arn" {
  value = aws_cognito_user_pool.user_pool.arn
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

output "api_gateway_url" {
  value = aws_api_gateway_stage.api_stage.invoke_url
}

output "lambda_function_arns" {
  value = { for k, v in aws_lambda_function.lambda_functions : k => v.arn }
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend_app.id
}

output "amplify_app_default_domain" {
  value = aws_amplify_app.frontend_app.default_domain
}
