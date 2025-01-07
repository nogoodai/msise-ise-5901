terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy the infrastructure."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the deployment stack."
  type        = string
}

variable "github_repository" {
  description = "The GitHub repository for the Amplify app."
  type        = string
}

variable "cognito_domain_prefix" {
  description = "The domain prefix for the Cognito user pool custom domain."
  type        = string
  default     = "myapp"
}

resource "aws_cognito_user_pool" "main" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "main" {
  domain     = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  write_capacity = 5
  read_capacity  = 5

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

resource "aws_api_gateway_rest_api" "main" {
  name        = "api-${var.stack_name}"
  description = "API for the serverless application"
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  name         = "cognito-authorizer"
  rest_api_id  = aws_api_gateway_rest_api.main.id
  identity_source = "method.request.header.Authorization"
  type         = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    rate_limit = 50
    burst_limit = 100
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "add_item" {
  filename         = "add-item.zip"
  function_name    = "add-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo.name
    }
  }
  tracing_config {
    mode = "Active"
  }
  publish = true
}

# Repeat the above lambda function resources for: 
# get_item, get_all_items, update_item, complete_item, delete_item

data "aws_iam_policy_document" "lambda_exec" {
  statement {
    actions = [
      "dynamodb:*",
      "cloudwatch:*"
    ]

    resources = [
      aws_dynamodb_table.todo.arn,
      "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

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
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "AllowDynamoDBAndCW"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_exec.json
}

resource "aws_amplify_app" "main" {
  name = "amplify-app-${var.stack_name}"

  source_code_management {
    repository = var.github_repository
  }

  build_spec = <<BUILD_SPEC
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - yarn install
    build:
      commands:
        - yarn build
  artifacts:
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/* 
BUILD_SPEC

  environment_variables = {
    NODE_ENV = "prod"
  }

  lifecycle {
    ignore_changes = [
      "name",
      "source_code_management.repository"
    ]
  }
}

resource "aws_amplify_branch" "main" {
  app_id     = aws_amplify_app.main.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway" {
  name = "api_gateway_role"

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
    name = "CloudWatchWritePolicy"
    policy = data.aws_iam_policy_document.apigateway_logs.json
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "apigateway_logs" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.main.invoke_url
}
