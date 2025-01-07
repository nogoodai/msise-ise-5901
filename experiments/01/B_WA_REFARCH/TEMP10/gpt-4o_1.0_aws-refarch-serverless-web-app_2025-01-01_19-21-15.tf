terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy to."
  default     = "us-east-1"
}

variable "app_name" {
  description = "The name of the application."
  default     = "todo-app"
}

variable "stack_name" {
  description = "The stack name for resources."
  default     = "prod"
}

variable "github_token" {
  description = "GitHub token for Amplify access."
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.app_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.app_name}-${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_AUTH_CODE_FLOW", "ALLOW_IMPLICIT_FLOW"]

  oauth {
    allowed_oauth_flows = ["code", "implicit"]
    allowed_oauth_scopes = ["email", "phone", "openid"]
    callback_urls = [/* Add callback URLs here */]
  }
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain      = "${var.app_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "data_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  hash_key = "cognito-username"
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

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.app_name}-${var.stack_name}-api"
  description = "API for managing to-do items."

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name    = "prod"

  variables = {
    "environment" = "production"
  }

  xray_tracing_enabled = true
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.app_name}-${var.stack_name}-plan"

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  api_stages {
    api_id    = aws_api_gateway_rest_api.api.id
    stage     = aws_api_gateway_stage.prod.stage_name
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.app_name}-add-item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  # Code package to be uploaded to S3
}

# Repeat Lambda configuration for other functions, changing names and handlers as needed.

resource "aws_amplify_app" "amplify_app" {
  name                   = "${var.app_name}-${var.stack_name}-frontend"
  platform               = "WEB"
  oauth_token            = var.github_token
  repository             = "https://github.com/yourorg/yourrepo"

  default_domain = "amplifyapp.example.com"
  
  build_spec = "# Your build spec goes here"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_amplify_branch" "master" {
  app_id     = aws_amplify_app.amplify_app.id
  branch_name = "master"
  
  framework    = "React" # or appropriate framework

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.app_name}-lambda-exec"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
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

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambdaPolicy"
  role = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions   = ["dynamodb:*"]
    resources = [aws_dynamodb_table.data_table.arn]
  }

  statement {
    actions = ["logs:*", "xray:PutTelemetryRecords", "xray:PutTraceSegments"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.app_name}-api-gateway-role"

  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json
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

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "apiGatewayPolicy"
  role = aws_iam_role.api_gateway_role.id
  policy = data.aws_iam_policy_document.api_gateway_policy.json
}

data "aws_iam_policy_document" "api_gateway_policy" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.app_name}-amplify-role"

  assume_role_policy = data.aws_iam_policy_document.amplify_assume_role_policy.json
}

data "aws_iam_policy_document" "amplify_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["amplify.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "amplifyPolicy"
  role = aws_iam_role.amplify_role.id
  policy = data.aws_iam_policy_document.amplify_policy.json
}

data "aws_iam_policy_document" "amplify_policy" {
  statement {
    actions   = ["amplify:*"]
    resources = ["*"]
  }
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.data_table.name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
