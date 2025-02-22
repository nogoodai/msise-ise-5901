```hcl
terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
  type        = string
}

variable "stack_name" {
  description = "Stack name for resource naming"
  default     = "todo-app"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  default     = "user/repo"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch for Amplify"
  default     = "master"
  type        = string
}

variable "cognito_domain" {
  description = "Custom domain for Cognito"
  default     = "auth.todo-app.com"
  type        = string
}

provider "aws" {
  region = var.region
}

resource "aws_cognito_user_pool" "todo_app_user_pool" {
  name = "${var.stack_name}-user-pool"

  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
  }

  mfa_configuration = "OPTIONAL"

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_cognito_user_pool_client" "todo_app_user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.todo_app_user_pool.id

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  generate_secret                      = false
  prevent_user_existence_errors        = "ENABLED"

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_cognito_user_pool_domain" "todo_app_user_pool_domain" {
  domain       = var.cognito_domain
  user_pool_id = aws_cognito_user_pool.todo_app_user_pool.id
}

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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_rest_api" "todo_app_api" {
  name        = "${var.stack_name}-api"
  description = "Todo App API"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = "todo-app"
  }
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
  description = "Usage plan for Todo App API"

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

  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_authorizer" "todo_app_authorizer" {
  name                   = "${var.stack_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.todo_app_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.todo_app_user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_method_settings" "todo_app_method_settings" {
  rest_api_id = aws_api_gateway_rest_api.todo_app_api.id
  stage_name  = aws_api_gateway_deployment.todo_app_deployment.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

resource "aws_lambda_function" "todo_app_lambda" {
  for_each = toset(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"])

  function_name = "${var.stack_name}-${each.key}"
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

  tags = {
    Name        = "${var.stack_name}-${each.key}"
    Environment = "prod"
    Project     = "todo-app"
  }

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  for_each      = aws_lambda_function.todo_app_lambda
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_app_api.execution_arn}/*/*"
}

resource "aws_amplify_app" "todo_app_amplify" {
  name       = "${var.stack_name}-amplify-app"
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
    Name        = "${var.stack_name}-amplify-app"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_amplify_branch" "todo_app_master_branch" {
  app_id      = aws_amplify_app.todo_app_amplify.id
  branch_name = var.github_branch

  framework = "React"
  enable_auto_build = true

  tags = {
    Name        = "${var.stack_name}-amplify-master-branch"
    Environment = "prod"
    Project     = "todo-app"
  }
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
    Environment = "prod"
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
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy" "amplify_manage_resources_policy" {
  name = "${var.stack_name}-amplify-manage-resources-policy"
  role = aws_iam_role.amplify_role.id

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
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
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
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  for_each = aws_lambda_function.todo_app_lambda

  alarm_name          = "${each.value.function_name}-Error-Alarm"
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
    Name        = "${each.value.function_name}-Error-Alarm"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_accessanalyzer_analyzer" "access_analyzer" {
  analyzer_name = "${var.stack_name}-access-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name        = "${var.stack_name}-access-analyzer"
    Environment = "prod"
    Project     = "todo-app"
  }
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.todo_app_user_pool.id
  description = "The ID of the Cognito User Pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.todo_app_user_pool_client.id
  description = "The ID of the Cognito User Pool Client"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.todo_app_user_pool_domain.domain
  description = "The custom domain of the Cognito User Pool"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_url" {
  value       = aws_api_gateway_deployment.todo_app_deployment.invoke_url
  description = "The invoke URL of the API Gateway deployment"
}

output "amplify_app_id" {
  value       = aws_amplify_app.todo_app_amplify.id
  description = "The ID of the Amplify App"
}

output "amplify_app_url" {
  value       = aws_amplify_app.todo_app_amplify.default_domain
  description = "The default domain of the Amplify App"
}
```