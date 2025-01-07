terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy resources"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "Name of the application stack"
}

variable "github_repo" {
  type        = string
  default     = "your-username/your-repo-name"
  description = "GitHub repository for Amplify hosting"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for Cognito custom domain"
}

variable "cognito_domain_prefix" {
  type        = string
  default     = "auth"
  description = "Prefix for Cognito custom domain"
}

# Provider
provider "aws" {
  region = var.region
}

# Data sources
data "aws_iam_policy_document" "api_gateway_cloudwatch_policy" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

data "aws_iam_policy_document" "amplify_policy" {
  statement {
    actions   = ["amplify:*"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "lambda_dynamodb_policy" {
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:${var.region}:*:table/todo-table-${var.stack_name}"]
  }
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:Scan", "dynamodb:Query"]
    resources = ["arn:aws:dynamodb:${var.region}:*:table/todo-table-${var.stack_name}"]
  }
}

data "aws_iam_policy_document" "lambda_cloudwatch_policy" {
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
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
      },
    ]
  })

  inline_policy {
    name   = "api-gateway-cloudwatch-policy"
    policy = data.aws_iam_policy_document.api_gateway_cloudwatch_policy.json
  }

  tags = {
    Name        = "${var.stack_name}-api-gateway-role"
    Environment = "prod"
    Project     = var.stack_name
  }
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
      },
    ]
  })

  inline_policy {
    name   = "amplify-policy"
    policy = data.aws_iam_policy_document.amplify_policy.json
  }

  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Environment = "prod"
    Project     = var.stack_name
  }
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
      },
    ]
  })

  inline_policy {
    name   = "lambda-dynamodb-policy"
    policy = data.aws_iam_policy_document.lambda_dynamodb_policy.json
  }

  inline_policy {
    name   = "lambda-cloudwatch-policy"
    policy = data.aws_iam_policy_document.lambda_cloudwatch_policy.json
  }

  tags = {
    Name        = "${var.stack_name}-lambda-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls        = ["https://${var.domain_name}/"]
  logout_urls          = ["https://${var.domain_name}/"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name = "${var.stack_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_resource" "item_id_resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.item_resource.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "item_done_resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.item_id_resource.id
  path_part   = "done"
}

resource "aws_api_gateway_method" "add_item" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_id_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "get_all_items" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "update_item" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_id_resource.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_method" "complete_item" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_done_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_id_resource.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.item_resource.id,
      aws_api_gateway_resource.item_id_resource.id,
      aws_api_gateway_resource.item_done_resource.id,
      aws_api_gateway_method.add_item.id,
      aws_api_gateway_method.get_item.id,
      aws_api_gateway_method.get_all_items.id,
      aws_api_gateway_method.update_item.id,
      aws_api_gateway_method.complete_item.id,
      aws_api_gateway_method.delete_item.id
    ]))
  }

  tags = {
    Name        = "${var.stack_name}-api-deployment"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
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
    Project     = var.stack_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_functions/add_item.zip"
  function_name = "${var.stack_name}-add-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

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
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_functions/get_item.zip"
  function_name = "${var.stack_name}-get-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

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
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_functions/get_all_items.zip"
  function_name = "${var.stack_name}-get-all-items"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

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
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_functions/update_item.zip"
  function_name = "${var.stack_name}-update-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

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
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_functions/complete_item.zip"
  function_name = "${var.stack_name}-complete-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

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
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_functions/delete_item.zip"
  function_name = "${var.stack_name}-delete-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

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
    Environment = "prod"
    Project     = var.stack_name
  }
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "add_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.add_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.add_item.invoke_arn
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
  http_method             = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_item.invoke_arn
}

resource "aws_api_gateway_integration" "get_all_items_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.get_all_items.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_all_items.invoke_arn
}

resource "aws_api_gateway_integration" "update_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
  http_method             = aws_api_gateway_method.update_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.update_item.invoke_arn
}

resource "aws_api_gateway_integration" "complete_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_done_resource.id
  http_method             = aws_api_gateway_method.complete_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.complete_item.invoke_arn
}

resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
  http_method             = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.delete_item.invoke_arn
}

# Lambda Permission
resource "aws_lambda_permission" "add_item_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_item_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_all_items_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_all_items.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "update_item_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_item.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "complete_item_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.complete_item.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "delete_item_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_item.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

# Amplify
resource "aws_amplify_app" "amplify_app" {
  name       = "${var.stack_name}-amplify-app"
  repository = var.github_repo

  build_spec = <<-EOT
    version: 1
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
    Name        = "${var.stack_name}-amplify-app"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.stack_name}-master-branch"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# CloudWatch Logs and Alarms
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.api_gateway.name}"

  tags = {
    Name        = "${aws_api_gateway_rest_api.api_gateway.name}-log-group"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = toset([
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.update_item.function_name,
    aws_lambda_function.complete_item.function_name,
    aws_lambda_function.delete_item.function_name
  ])
  name = "/aws/lambda/${each.value}"

  tags = {
    Name        = "${each.value}-log-group"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors_alarm" {
  for_each = toset([
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.update_item.function_name,
    aws_lambda_function.complete_item.function_name,
    aws_lambda_function.delete_item.function_name
  ])

  alarm_name          = "${each.value}-Errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${each.value}"
  alarm_actions       = []  # Add SNS topic ARN here for notifications

  dimensions = {
    FunctionName = each.value
  }

  tags = {
    Name        = "${each.value}-Errors-Alarm"
    Environment = "prod"
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
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_app_default_domain" {
  value = aws_amplify_app.amplify_app.default_domain
}
