terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Stack name for naming resources"
  default     = "my-stack"
}

variable "github_repository" {
  description = "GitHub repository URL for Amplify"
}

variable "amplify_branch_name" {
  description = "GitHub branch name for Amplify"
  default     = "master"
}

resource "aws_cognito_user_pool" "main" {
  name = "user-pool-${var.stack_name}"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_AUTH_CODE_FLOW", "ALLOW_IMPLICIT_FLOW"]

  supported_identity_providers = ["COGNITO"]

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  generate_secret = false
}

resource "aws_dynamodb_table" "todo" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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

resource "aws_apigatewayv2_api" "main" {
  name          = "api-gateway-${var.stack_name}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id       = aws_apigatewayv2_api.main.id
  name         = "prod"
  auto_deploy  = true
}

resource "aws_apigatewayv2_authorizer" "cognito_auth" {
  name       = "cognito-authorizer-${var.stack_name}"
  api_id     = aws_apigatewayv2_api.main.id
  identity_sources = ["$request.header.Authorization"]

  authorizer_type = "JWT"
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.main.id]
    issuer   = "${aws_cognito_user_pool.main.endpoint}/"
  }
}

resource "aws_lambda_function" "crud" {
  function_name = "crud-function-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  code {
    s3_bucket = "<Your_S3_Bucket>"
    s3_key    = "<Your_S3_Key>"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo.name
    }
  }
}

resource "aws_lambda_permission" "api_gateway" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-${var.stack_name}"
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

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_amplify_app" "web" {
  name                  = "${var.stack_name}-amplify-app"
  repository            = var.github_repository

  build_spec = <<SPEC
version: 1
frontend:
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
SPEC
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.web.id
  branch_name = var.amplify_branch_name
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

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

  policies = ["arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"]
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "lambda_function_arn" {
  value = aws_lambda_function.crud.arn
}

output "api_gateway_url" {
  value = aws_apigatewayv2_stage.prod.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.web.default_domain
}
