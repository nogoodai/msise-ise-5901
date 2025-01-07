terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Stack name for resource identification"
  type        = string
  default     = "todo-app"
}

variable "domain_name" {
  description = "Custom domain name for Cognito"
  type        = string
  default     = "auth.todo-app.com"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  type        = string
  default     = "username/todo-app-frontend"
}

# Provider Configuration
provider "aws" {
  region = var.region
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
    Environment = "Production"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name = "${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false

  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "Production"
    Project     = var.stack_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = var.domain_name
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name        = "${var.stack_name}-user-pool-domain"
    Environment = "Production"
    Project     = var.stack_name
  }
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
    Environment = "Production"
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for To-Do App"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "Production"
    Project     = var.stack_name
  }
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.stack_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api_gateway.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api_gateway.body))
  }

  depends_on = [aws_api_gateway_method.api_methods]
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name         = "${var.stack_name}-usage-plan"
  description  = "Usage plan for To-Do App API"
  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
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
    Environment = "Production"
    Project     = var.stack_name
  }
}

# Lambda Functions
locals {
  lambda_functions = [
    { name = "add-item", method = "POST", path = "/item", type = "write" },
    { name = "get-item", method = "GET", path = "/item/{id}", type = "read" },
    { name = "get-all-items", method = "GET", path = "/item", type = "read" },
    { name = "update-item", method = "PUT", path = "/item/{id}", type = "write" },
    { name = "complete-item", method = "POST", path = "/item/{id}/done", type = "write" },
    { name = "delete-item", method = "DELETE", path = "/item/{id}", type = "write" }
  ]
}

resource "aws_lambda_function" "lambda_functions" {
  for_each = { for func in local.lambda_functions : func.name => func }

  function_name = "${var.stack_name}-${each.value.name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename      = "lambda_function_payload.zip"

  role = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-${each.value.name}"
    Environment = "Production"
    Project     = var.stack_name
  }

  tracing_config {
    mode = "Active"
  }
}

# API Gateway Methods and Integrations
resource "aws_api_gateway_resource" "api_resources" {
  for_each = { for func in local.lambda_functions : func.path => func }

  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = each.key
}

resource "aws_api_gateway_method" "api_methods" {
  for_each = { for func in local.lambda_functions : func.path => func }

  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.api_resources[each.key].id
  http_method   = each.value.method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "api_integrations" {
  for_each = { for func in local.lambda_functions : func.path => func }

  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.api_resources[each.key].id
  http_method = aws_api_gateway_method.api_methods[each.key].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_functions[each.value.name].invoke_arn
}

# Lambda Permissions
resource "aws_lambda_permission" "api_gateway_lambda_permissions" {
  for_each = { for func in local.lambda_functions : func.name => func }

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_functions[each.key].function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/${aws_api_gateway_method.api_methods[each.value.path].http_method}${aws_api_gateway_resource.api_resources[each.value.path].path}"
}

# IAM Roles and Policies
# API Gateway Role
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
    Environment = "Production"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "Policy for API Gateway to log to CloudWatch"

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
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = {
    Name        = "${var.stack_name}-api-gateway-policy"
    Environment = "Production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

# Amplify Role
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
    Environment = "Production"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Policy for Amplify to manage resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "amplify:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.stack_name}-amplify-policy"
    Environment = "Production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Lambda Role
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
    Environment = "Production"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.stack_name}-lambda-dynamodb-policy"
  description = "Policy for Lambda to interact with DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
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

  tags = {
    Name        = "${var.stack_name}-lambda-dynamodb-policy"
    Environment = "Production"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name        = "${var.stack_name}-lambda-cloudwatch-policy"
  description = "Policy for Lambda to publish metrics to CloudWatch"

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
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-cloudwatch-policy"
    Environment = "Production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
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
    Environment = "Production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.stack_name}-master-branch"
    Environment = "Production"
    Project     = var.stack_name
  }
}

# Monitoring and Alerting
# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "lambda_log_groups" {
  for_each = { for func in local.lambda_functions : func.name => func }

  name              = "/aws/lambda/${var.stack_name}-${each.value.name}"
  retention_in_days = 14

  tags = {
    Name        = "${var.stack_name}-${each.value.name}-log-group"
    Environment = "Production"
    Project     = var.stack_name
  }
}

# CloudWatch Alarms for Lambda Functions
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarms" {
  for_each = { for func in local.lambda_functions : func.name => func }

  alarm_name          = "${var.stack_name}-${each.value.name}-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${each.value.name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.lambda_functions[each.key].function_name
  }

  tags = {
    Name        = "${var.stack_name}-${each.value.name}-error-alarm"
    Environment = "Production"
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

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "lambda_function_arns" {
  value = { for func in local.lambda_functions : func.name => aws_lambda_function.lambda_functions[func.name].arn }
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}
