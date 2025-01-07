terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "The name of the project."
  type        = string
  default     = "my-serverless-app"
}

variable "stack_name" {
  description = "The name of the stack."
  type        = string
  default     = "prod"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  policies {
    password_policy {
      minimum_length    = 6
      require_lowercase = true
      require_uppercase = true
      require_numbers   = false
      require_symbols   = false
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "this" {
  user_pool_id = aws_cognito_user_pool.this.id
  name         = "${var.project_name}-${var.stack_name}-user-pool-client"

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows = ["code", "implicit"]

  allowed_oauth_scopes = ["email", "openid", "phone"]

  generate_secret = false

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.project_name}-${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# API Gateway

resource "aws_api_gateway_rest_api" "this" {
  name = "${var.project_name}-${var.stack_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.this.id

  deployment {
    full_access_log_group_arn = aws_cloudwatch_log_group.api_logs.arn
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-stage"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_throttle_settings" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = aws_api_gateway_stage.prod.stage_name
  hourly_limit  = 5000
  burst_limit   = 100
  rate_limit    = 50
}

# Lambda Functions

resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "add-item.handler"
  role          = aws_iam_role.lambda_exec.arn

  memory_size = 1024
  timeout     = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Additional lambda functions (get, update, delete) here...

# Amplify App

resource "aws_amplify_app" "this" {
  name = "${var.project_name}-${var.stack_name}-amplify"

  repository = "https://github.com/username/repo.git"
  branch     = "master"
  oauth_token = var.github_token

  build_spec = <<EOF
version: 1
applications:
  - frontend:
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
      cache:
        paths:
          - node_modules/**/*
EOF

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-amplify"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "this" {
  app_id = aws_amplify_app.this.id
  branch_name = "master"

  enable_auto_build = true

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-amplify-branch"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# IAM Roles and Policies

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-${var.stack_name}-lambda-exec-role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.project_name}-${var.stack_name}-lambda-policy"

  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "cloudwatch:PutMetricData",
    ]

    resources = [aws_dynamodb_table.this.arn]
  }
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.this.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.this.name
}

output "api_gateway_url" {
  description = "The URL of the API Gateway."
  value       = aws_api_gateway_deployment.prod.invoke_url
}

output "amplify_app_id" {
  description = "The ID of the Amplify app."
  value       = aws_amplify_app.this.id
}
