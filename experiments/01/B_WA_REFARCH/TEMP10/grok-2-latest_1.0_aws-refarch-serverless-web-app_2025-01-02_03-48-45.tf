terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "aws_region" {
  description = "AWS region for resources"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Name of the stack for resource naming"
  default     = "todo-app"
}

variable "github_repo" {
  description = "GitHub repository for Amplify source"
  default     = "user/repo"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the custom Cognito domain"
  default     = "auth"
}

# Provider
provider "aws" {
  region = var.aws_region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app_user_pool" {
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
    Environment = "production"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app_client" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.todo_app_user_pool.id

  explicit_auth_flows = ["ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret     = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.stack_name}-client"
    Environment = "production"
    Project     = var.stack_name
  }
}

# Custom Domain for Cognito
resource "aws_cognito_user_pool_domain" "todo_app_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_app_user_pool.id
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
resource "aws_api_gateway_rest_api" "todo_app_api" {
  name        = "${var.stack_name}-api"
  description = "API for todo application"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_app_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app_user_pool.arn]
}

resource "aws_api_gateway_deployment" "todo_app_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_app_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "todo_app_usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for todo application"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_app_api.id
    stage  = aws_api_gateway_deployment.todo_app_deployment.stage_name
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
locals {
  lambda_functions = [
    {
      name        = "addItem"
      description = "Add a new item to the todo list"
      method      = "POST"
      path        = "/item"
    },
    {
      name        = "getItem"
      description = "Retrieve a specific item from the todo list"
      method      = "GET"
      path        = "/item/{id}"
    },
    {
      name        = "getAllItems"
      description = "Retrieve all items from the todo list"
      method      = "GET"
      path        = "/item"
    },
    {
      name        = "updateItem"
      description = "Update an existing item in the todo list"
      method      = "PUT"
      path        = "/item/{id}"
    },
    {
      name        = "completeItem"
      description = "Mark an item as complete in the todo list"
      method      = "POST"
      path        = "/item/{id}/done"
    },
    {
      name        = "deleteItem"
      description = "Delete an item from the todo list"
      method      = "DELETE"
      path        = "/item/{id}"
    },
  ]
}

resource "aws_lambda_function" "todo_app_lambda" {
  for_each = { for fn in local.lambda_functions : fn.name => fn }

  function_name = "${var.stack_name}-${each.value.name}"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_function_payload.zip"

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-${each.value.name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  for_each      = aws_lambda_function.todo_app_lambda
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_app_api.execution_arn}/*/*"
}

resource "aws_api_gateway_resource" "todo_app_resource" {
  for_each    = { for fn in local.lambda_functions : fn.path => fn if fn.path != "/item" }
  rest_api_id = aws_api_gateway_rest_api.todo_app_api.id
  parent_id   = aws_api_gateway_rest_api.todo_app_api.root_resource_id
  path_part   = each.key
}

resource "aws_api_gateway_method" "todo_app_method" {
  for_each      = { for fn in local.lambda_functions : "${fn.method}/${fn.path}" => fn }
  rest_api_id   = aws_api_gateway_rest_api.todo_app_api.id
  resource_id   = each.value.path == "/item" ? aws_api_gateway_rest_api.todo_app_api.root_resource_id : aws_api_gateway_resource.todo_app_resource[each.value.path].id
  http_method   = each.value.method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.id" = true
  }
}

resource "aws_api_gateway_integration" "todo_app_integration" {
  for_each                = aws_api_gateway_method.todo_app_method
  rest_api_id             = aws_api_gateway_rest_api.todo_app_api.id
  resource_id             = each.value.resource_id
  http_method             = each.value.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.todo_app_lambda["${each.value.path == "/item" ? "getAllItems" : split("/", each.key)[1]}"].invoke_arn

  request_parameters = {
    "integration.request.path.id" = "method.request.path.id"
  }
}

# Amplify App
resource "aws_amplify_app" "todo_app_amplify" {
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

  environment_variables = {
    ENV = "prod"
  }

  tags = {
    Name        = "${var.stack_name}-frontend"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "todo_app_master_branch" {
  app_id      = aws_amplify_app.todo_app_amplify.id
  branch_name = "master"

  tags = {
    Name        = "${var.stack_name}-master-branch"
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
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
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

resource "aws_iam_role" "lambda_execution_role" {
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
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "dynamodb:GetItem",
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
  role = aws_iam_role.lambda_execution_role.id

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
        Resource = "arn:aws:logs:*:*:*"
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
  name              = "/aws/api-gateway/${var.stack_name}-api"
  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-api-logs"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  alarm_name          = "${var.stack_name}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors 5XX errors for the API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.todo_app_api.name
  }

  tags = {
    Name        = "${var.stack_name}-api-5xx-alarm"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = aws_lambda_function.todo_app_lambda

  name              = "/aws/lambda/${each.value.function_name}"
  retention_in_days = 30

  tags = {
    Name        = "${each.value.function_name}-logs"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = aws_lambda_function.todo_app_lambda

  alarm_name          = "${each.value.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors errors for the Lambda function ${each.value.function_name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${each.value.function_name}-errors-alarm"
    Environment = "production"
    Project     = var.stack_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app_user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.todo_app_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_app_deployment.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.todo_app_amplify.default_domain
}
