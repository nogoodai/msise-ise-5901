terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region for the deployment"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name used in resource naming"
  type        = string
  default     = "prod"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify"
  type        = string
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }
  
  mfa_configuration = "ON"

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "user-pool-client-${var.stack_name}"

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = true
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "todo-api-${var.stack_name}"
  description = "API Gateway for to-do app"

  endpoint_configuration {
    types = ["PRIVATE"]
  }
  
  minimum_compression_size = 0

  tags = {
    Name        = "todo-api-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_log.arn
    format          = "$context.requestId $context.identity.sourceIp $context.identity.caller $context.identity.user $context.requestTime $context.httpMethod $context.resourcePath $context.status $context.protocol $context.responseLength"
  }

  tags = {
    Name        = "api-stage-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode(aws_lambda_function.lambda_functions))
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
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

  tags = {
    Name        = "usage-plan-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-exec-${var.stack_name}"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json

  tags = {
    Name        = "lambda-exec-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "lambda-policy-${var.stack_name}"
  policy = data.aws_iam_policy_document.lambda_policy.json

  tags = {
    Name        = "lambda-policy-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions   = ["dynamodb:*"]
    resources = [aws_dynamodb_table.todo_table.arn]
  }

  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
}

resource "aws_lambda_function" "lambda_functions" {
  for_each = toset(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"])

  function_name = "${each.key}-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  memory_size   = 1024
  timeout       = 60

  role    = aws_iam_role.lambda_role.arn
  filename = "path/to/${each.key}.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${each.key}-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

data "aws_iam_policy_document" "api_gateway_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name   = "api-gateway-policy-${var.stack_name}"
  policy = data.aws_iam_policy_document.api_gateway_policy.json

  tags = {
    Name        = "api-gateway-policy-${var.stack_name}"
    Environment = "production"
    Project     = "todo"
  }
}

data "aws_iam_policy_document" "api_gateway_policy" {
  statement {
    actions   = ["logs:*"]
    resources = ["*"]
  }
}

resource "aws_amplify_app" "amplify_app" {
  name               = "amplify-app-${var.stack_name}"
  repository         = var.github_repo
  branch_auto_build  = true

  default_domain_association = true

  build_spec = <<EOF
version: 1
backend:
  phases:
    build:
      commands:
        - npm install
        - npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
}

resource "aws_cloudwatch_log_group" "api_gw_log" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.api.name}"
  retention_in_days = 90
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "ID of the Cognito User Pool"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "Name of the DynamoDB table"
}

output "api_gateway_url" {
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
  description = "Invoke URL of the API Gateway"
}

output "amplify_app_url" {
  value       = aws_amplify_app.amplify_app.default_domain
  description = "Default domain of the Amplify App"
}
