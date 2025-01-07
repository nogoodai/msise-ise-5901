terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy to."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack."
}

variable "project_name" {
  description = "The name of the project."
}

variable "github_repo" {
  description = "The GitHub repository URL for the frontend application."
}

data "aws_caller_identity" "current" {}

locals {
  tags = {
    Name        = "${var.project_name}-${var.stack_name}"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = local.tags
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "${var.project_name}-${var.stack_name}-client"

  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  generate_secret = false

  tags = local.tags
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.project_name}-${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo" {
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

  tags = local.tags
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.project_name}-api"
  description = "API Gateway for the ToDo application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.tags
}

resource "aws_api_gateway_authorizer" "cognito" {
  name        = "cognito-authorizer"
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]

  identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
  deployment {
    create_before_destroy = true
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-add-item"
  filename      = "add_item.zip" # Path to your function zip file
  handler       = "index.handler" # Update with your handler
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn

  memory_size = 1024
  timeout     = 60

  tracing_config {
    mode = "Active"
  }

  tags = local.tags
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  role   = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:*",
          "logs:*",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "api_gateway" {
  name = "${var.project_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  role   = aws_iam_role.api_gateway.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "logs:CreateLogGroup"
        Effect = "Allow"
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_amplify_app" "frontend" {
  name           = "${var.project_name}-amplify-${var.stack_name}"
  repository     = var.github_repo
  branch         = "main"

  iam_service_role_arn = aws_iam_role.amplify_exec.arn

  tags = local.tags
}

resource "aws_iam_role" "amplify_exec" {
  name = "${var.project_name}-amplify-exec-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "amplify_exec_policy" {
  role = aws_iam_role.amplify_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
          "s3:*",
          "cloudwatch:*"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "api_gateway_url" {
  value = "${aws_api_gateway_rest_api.todo_api.execution_arn}/prod/"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}
