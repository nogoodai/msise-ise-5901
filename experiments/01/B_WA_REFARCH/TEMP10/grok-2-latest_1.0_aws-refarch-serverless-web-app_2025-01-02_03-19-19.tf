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
  default = "us-east-1"
}

variable "app_name" {
  default = "todo-app"
}

variable "stack_name" {
  default = "production"
}

variable "cognito_domain_prefix" {
  default = "auth"
}

variable "github_repo" {
  default = "username/todo-app"
}

variable "github_branch" {
  default = "master"
}

# Networking and Security
resource "aws_cognito_user_pool" "todo_user_pool" {
  name = "${var.app_name}-${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cognito_user_pool_client" "todo_user_pool_client" {
  name = "${var.app_name}-${var.stack_name}-client"

  user_pool_id = aws_cognito_user_pool.todo_user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-client"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cognito_user_pool_domain" "todo_user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.app_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_user_pool.id

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-domain"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Data Storage
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
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name = "${var.app_name}-${var.stack_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  name        = "${var.app_name}-${var.stack_name}-cognito-authorizer"

  type = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_user_pool.arn]
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.add_item_integration,
    aws_api_gateway_integration.get_item_integration,
    aws_api_gateway_integration.get_all_items_integration,
    aws_api_gateway_integration.update_item_integration,
    aws_api_gateway_integration.complete_item_integration,
    aws_api_gateway_integration.delete_item_integration,
  ]
}

resource "aws_api_gateway_method_settings" "todo_api_settings" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = aws_api_gateway_deployment.todo_api_deployment.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name = "${var.app_name}-${var.stack_name}-usage-plan"

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
    Name        = "${var.app_name}-${var.stack_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.app_name}-${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  filename      = "lambda_add_item.zip"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.app_name}-${var.stack_name}-get-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  filename      = "lambda_get_item.zip"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-get-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.app_name}-${var.stack_name}-get-all-items"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  filename      = "lambda_get_all_items.zip"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-get-all-items"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.app_name}-${var.stack_name}-update-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  filename      = "lambda_update_item.zip"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-update-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.app_name}-${var.stack_name}-complete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  filename      = "lambda_complete_item.zip"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-complete-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.app_name}-${var.stack_name}-delete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  filename      = "lambda_delete_item.zip"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-delete-item"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# API Gateway Integration with Lambda Functions
resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "add_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration" "add_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.add_item_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.add_item.invoke_arn
}

resource "aws_api_gateway_method" "get_all_items_method" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "get_all_items_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.get_all_items_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_all_items.invoke_arn
}

resource "aws_api_gateway_resource" "item_id" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_resource.item.id
  path_part   = "{id}"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.get_item_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_item.invoke_arn
}

resource "aws_api_gateway_method" "update_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "update_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.update_item_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.update_item.invoke_arn
}

resource "aws_api_gateway_resource" "item_done" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_resource.item_id.id
  path_part   = "done"
}

resource "aws_api_gateway_method" "complete_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item_done.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "complete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_done.id
  http_method = aws_api_gateway_method.complete_item_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.complete_item.invoke_arn
}

resource "aws_api_gateway_method" "delete_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.delete_item_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.delete_item.invoke_arn
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name       = "${var.app_name}-${var.stack_name}"
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

  enable_auto_branch_creation = false

  environment_variables = {
    ENV = var.stack_name
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-app"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_amplify_branch" "todo_master_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch

  framework = "React"
  stage     = "PRODUCTION"

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-master-branch"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.app_name}-${var.stack_name}-api-gateway-role"

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
    Name        = "${var.app_name}-${var.stack_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.app_name}-${var.stack_name}-api-gateway-cloudwatch-policy"
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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.app_name}-${var.stack_name}-amplify-role"

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
    Name        = "${var.app_name}-${var.stack_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_iam_role_policy" "amplify_resource_management_policy" {
  name = "${var.app_name}-${var.stack_name}-amplify-resource-management-policy"
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
  name = "${var.app_name}-${var.stack_name}-lambda-role"

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
    Name        = "${var.app_name}-${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.app_name}-${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:BatchGet*",
          "dynamodb:DescribeStream",
          "dynamodb:DescribeTable",
          "dynamodb:Get*",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWrite*",
          "dynamodb:CreateTable",
          "dynamodb:Delete*",
          "dynamodb:Update*",
          "dynamodb:PutItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.app_name}-${var.stack_name}-lambda-cloudwatch-policy"
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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.todo_api.name}"

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-api-gateway-log-group"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = toset([
    "add-item",
    "get-item",
    "get-all-items",
    "update-item",
    "complete-item",
    "delete-item"
  ])

  name = "/aws/lambda/${var.app_name}-${var.stack_name}-${each.value}"

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-${each.value}-log-group"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors_alarm" {
  for_each = toset([
    "add-item",
    "get-item",
    "get-all-items",
    "update-item",
    "complete-item",
    "delete-item"
  ])

  alarm_name          = "${var.app_name}-${var.stack_name}-${each.value}-errors-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors errors in the Lambda function ${each.value}"
  alarm_actions       = []

  dimensions = {
    FunctionName = "${var.app_name}-${var.stack_name}-${each.value}"
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-${each.value}-errors-alarm"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors_alarm" {
  alarm_name          = "${var.app_name}-${var.stack_name}-api-gateway-5xx-errors-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors 5XX errors in the API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.todo_api.name
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-api-gateway-5xx-errors-alarm"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_user_pool_client.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.todo_user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_api_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_app_default_domain" {
  value = aws_amplify_app.todo_app.default_domain
}

# Data Sources
data "aws_caller_identity" "current" {}
