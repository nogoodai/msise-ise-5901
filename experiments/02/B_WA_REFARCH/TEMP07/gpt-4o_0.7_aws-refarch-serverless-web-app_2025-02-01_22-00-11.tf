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
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for naming resources."
  type        = string
  default     = "my-stack"
}

variable "github_repository" {
  description = "The GitHub repository for the Amplify app."
  type        = string
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  policies {
    password_policy {
      minimum_length    = 6
      require_uppercase = true
      require_lowercase = true
      require_numbers   = false
      require_symbols   = false
    }
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false

  allowed_oauth_flows = [
    "code",
    "implicit"
  ]

  allowed_oauth_scopes = [
    "email",
    "phone",
    "openid"
  ]

  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
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
}

resource "aws_apigatewayv2_api" "api_gateway" {
  name          = "api-gateway-${var.stack_name}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "api_gateway_stage" {
  api_id = aws_apigatewayv2_api.api_gateway.id
  name   = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_log.arn
    format          = "$context.requestId $context.identity.sourceIp $context.path $context.protocol $context.status"
  }
}

resource "aws_cloudwatch_log_group" "api_gw_log" {
  name              = "/aws/apigateway/${aws_apigatewayv2_api.api_gateway.name}"
  retention_in_days = 7
}

resource "aws_lambda_function" "crud_lambda" {
  for_each = {
    "add_item"      = "POST /item",
    "get_item"      = "GET /item/{id}",
    "get_all_items" = "GET /item",
    "update_item"   = "PUT /item/{id}",
    "complete_item" = "POST /item/{id}/done",
    "delete_item"   = "DELETE /item/{id}"
  }

  function_name = "${each.key}-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  inline_policy {
    name = "dynamodb-access"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = [
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem"
          ]
          Resource = aws_dynamodb_table.todo_table.arn
        },
        {
          Effect   = "Allow"
          Action   = [
            "dynamodb:GetItem",
            "dynamodb:Scan"
          ]
          Resource = aws_dynamodb_table.todo_table.arn
        },
        {
          Effect   = "Allow"
          Action   = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "*"
        },
        {
          Effect   = "Allow"
          Action   = "xray:PutTelemetryRecords"
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-app-${var.stack_name}"

  repository = var.github_repository

  build_spec = <<EOF
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
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*

EOF

  auto_branch_creation {
    patterns = ["*"]
    basic_auth_credentials {
      username = "user"
      password = "pass"
    }
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id     = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_endpoint" {
  description = "The endpoint URL of the API Gateway"
  value       = aws_apigatewayv2_api.api_gateway.api_endpoint
}

output "amplify_app_id" {
  description = "The ID of the Amplify App"
  value       = aws_amplify_app.amplify_app.id
}
