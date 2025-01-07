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
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack for resource naming."
  type        = string
  default     = "my-stack"
}

locals {
  todo_table_name = "todo-table-${var.stack_name}"
}

resource "aws_cognito_user_pool" "main" {
  name                        = "${var.stack_name}-user-pool"
  auto_verified_attributes    = ["email"]
  username_attributes         = ["email"]
  
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "${var.stack_name}-user-pool-client"

  explicit_auth_flows        = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
  generate_secret            = false
  o_auth_flows               = ["code", "implicit"]
  o_auth_scopes              = ["email", "phone", "openid"]
  allowed_o_auth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "main" {
  domain        = "${var.stack_name}-auth"
  user_pool_id  = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = local.todo_table_name
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

resource "aws_iam_role" "lambda_execution" {
  name = "${var.stack_name}-lambda-exec-role"

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
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  role = aws_iam_role.lambda_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
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
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  role = aws_iam_role.api_gateway_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for handling to-do tasks"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  provider_arns = [aws_cognito_user_pool.main.arn]
}

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "add_item" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_cognito_user_pool.main.id
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  filename      = "add_item_function.zip"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_execution.arn
  memory_size   = 1024
  timeout       = 60
  
  tracing_config {
    mode = "Active"
  }
}

resource "aws_amplify_app" "frontend" {
  name             = "${var.stack_name}-frontend"
  repository       = "https://github.com/yourusername/repository.git"
  build_spec       = file("amplify_build_spec.yml")

  environment_variables = {
    STACK_NAME = var.stack_name
  }

  custom_rules {
    source    = "</^[^.]+$|\\.(?!(html|json)$)([^.]+$)/>"
    target    = "/index.html"
    status    = "200"
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_endpoint" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
