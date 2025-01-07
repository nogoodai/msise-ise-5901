terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources into"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for naming resources"
  default     = "myapp"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "user-pool-client-${var.stack_name}"

  explicit_auth_flows = ["ALLOW_AUTH_CODE_FLOW", "ALLOW_IMPLICIT_FLOW"]

  allowed_oauth_scopes = ["email", "openid", "phone"]

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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
}

data "aws_iam_policy_document" "api_gateway_logging" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name               = "api-gateway-role-${var.stack_name}"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_logging.json
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  # CORS configuration - global for all methods
  cors_configuration {
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    allow_origins = ["*"]
  }

  policy = aws_iam_policy_document.api_gateway_logging.json
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                    = "cognito_authorizer"
  rest_api_id             = aws_api_gateway_rest_api.api.id
  type                    = "COGNITO_USER_POOLS"
  provider_arns           = [aws_cognito_user_pool.user_pool.arn]
  identity_source         = "method.request.header.Authorization"
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.api.id
  deployment_id        = aws_api_gateway_deployment.deployment.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log.arn
    format          = "$context.requestId: $context.status, $context.responseLength"
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  api_stages {
    api_id         = aws_api_gateway_rest_api.api.id
    stage          = aws_api_gateway_stage.api_stage.stage_name
  }
}

resource "aws_lambda_function" "lambda_function" {
  function_name = "function-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_role.arn
}

resource "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions   = ["dynamodb:*"]
    resources = [aws_dynamodb_table.todo_table.arn]
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name   = "lambda-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  inline_policy {
    name   = "lambda-inline-policy"
    policy = aws_iam_policy_document.lambda_policy.json
  }
}

resource "aws_amplify_app" "frontend_app" {
  name  = "frontend-${var.stack_name}"
  repository = "git@github.com:yourusername/yourrepo.git"

  build_spec = <<-EOT
    version: 1.0
    frontend:
      phases:
        preBuild:
          commands:
            - npm install
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: /build
        files:
          - '**/*'
    EOT

  custom_rules {
    source = "/<*>"
    target = "/index.html"
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id = aws_amplify_app.frontend_app.id
  branch_name = "master"
  enable_auto_build = true
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.api_stage.invoke_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "amplify_app_url" {
  value = aws_amplify_app.frontend_app.default_domain
}
