terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "stack_name" {
  default = "my-app-stack"
}

variable "environment" {
  default = "prod"
}

variable "github_repo" {
  description = "GitHub repository for Amplify app source"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }

  tags = {
    Name       = "cognito-user-pool"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "user-pool-client-${var.stack_name}"

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  callback_urls       = ["https://example.com/callback", "https://example.com/logout"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  tags = {
    Name       = "cognito-user-pool-client"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain        = "auth-${var.stack_name}"
  user_pool_id  = aws_cognito_user_pool.user_pool.id

  tags = {
    Name       = "cognito-user-pool-domain"
    Environment = var.environment
    Project     = var.stack_name
  }
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
    Name       = "dynamodb-todo-table"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for managing to-do items"
}

resource "aws_api_gateway_stage" "stage" {
  stage_name    = var.environment
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id

  tags = {
    Name       = "api-gateway-stage"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on  = [aws_api_gateway_method.example]
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.stage.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  tags = {
    Name       = "api-gateway-usage-plan"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# Lambda Functions
locals {
  lambda_role_arn = "arn:aws:iam::123456789012:role/lambda-execution-role"
}

resource "aws_lambda_function" "add_item_function" {
  filename         = "lambda.zip"
  function_name    = "add-item-${var.stack_name}"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = local.lambda_role_arn

  tracing_config {
    mode = "Active"
  }
  
  tags = {
    Name       = "lambda-add-item"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# Continue defining other lambda functions similarly...

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name         = "frontend-${var.stack_name}"
  repository   = var.github_repo
  environment_variables = {
    ENVIRONMENT = var.environment
  }

  build_spec = <<BUILD_SPEC
version: 1
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
  cache:
    paths:
      - node_modules/**/*

BUILD_SPEC

  tags = {
    Name       = "amplify-frontend"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "main_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name       = "amplify-frontend-master"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# IAM Roles and Policies
data "aws_iam_policy_document" "api_gateway" {
  statement {
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
    effect    = "Allow"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })

  inline_policy {
    name   = "api-gateway-logging"
    policy = data.aws_iam_policy_document.api_gateway.json
  }

  tags = {
    Name       = "api-gateway-iam-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
