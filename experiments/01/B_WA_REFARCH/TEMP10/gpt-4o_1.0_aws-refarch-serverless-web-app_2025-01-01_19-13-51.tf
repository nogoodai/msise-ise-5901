terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Stack name for resource naming"
  default     = "my-stack"
}

variable "github_repository" {
  description = "GitHub repository URL for Amplify"
  default     = "https://github.com/user/repo"
}

resource "aws_cognito_user_pool" "this" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name                   = "${var.stack_name}-user-pool-client"
  user_pool_id           = aws_cognito_user_pool.this.id
  generate_secret        = false
  allowed_oauth_flows    = ["code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
}

resource "aws_route53_zone" "this" {
  name = "${var.stack_name}.example.com"
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}.auth.${var.region}.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.this.id

  custom_domain_config {
    certificate_arn = "arn:aws:acm:..."
  }
}

resource "aws_dynamodb_table" "this" {
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

resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name} application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  filename      = "path/to/add_item.zip"

  memory_size = 1024
  timeout     = 60

  tracing_config {
    mode = "Active"
  }
}

// Repeat for other Lambda functions, updating the handler and filename

resource "aws_amplify_app" "this" {
  name                = "${var.stack_name}-amplify-app"
  repository          = var.github_repository

  build_spec = <<BUILD_SPEC
version: 1
frontend:
  phases:
    pre_build:
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

BUILD_SPEC
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"

  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-apigateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apigateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.this.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.this.name
}

output "api_gateway_url" {
  description = "Base URL of the API Gateway"
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "amplify_app_id" {
  description = "ID of the Amplify App"
  value       = aws_amplify_app.this.id
}
