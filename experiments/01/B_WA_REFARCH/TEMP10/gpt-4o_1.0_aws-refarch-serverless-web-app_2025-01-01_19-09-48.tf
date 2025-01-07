terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  default = "prod"
}

variable "app_name" {
  default = "todo"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.app_name}-user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

  username_attributes     = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                      = "${var.app_name}-client-${var.stack_name}"
  user_pool_id              = aws_cognito_user_pool.user_pool.id
  generate_secret           = false
  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "${var.app_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
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

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.app_name}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id    = aws_apigatewayv2_api.api.id
  name      = "prod"
  auto_deploy = true
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id          = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = aws_cognito_user_pool.user_pool.endpoint
  }
}

resource "aws_apigatewayv2_usage_plan" "usage_plan" {
  name = "${var.app_name}-usage-plan"

  api_stages {
    api_id   = aws_apigatewayv2_api.api.id
    stage    = aws_apigatewayv2_stage.api_stage.name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "crud_functions" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.app_name}-lambda-${var.stack_name}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.app_name}-lambda-role-${var.stack_name}"

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
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.app_name}-lambda-policy-${var.stack_name}"
  role = aws_iam_role.lambda_role.id

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
          "dynamodb:Scan"
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

resource "aws_amplify_app" "amplify_app" {
  name = "${var.app_name}-amplify-${var.stack_name}"
  repository = "https://github.com/your-repo-name/your-app"

  auto_branch_creation_config {
    enable_auto_build = true
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.app_name}-amplify-role-${var.stack_name}"

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
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.app_name}-api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        "Service" : "apigateway.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.app_name}-api-gateway-policy-${var.stack_name}"
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

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.crud_functions.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
