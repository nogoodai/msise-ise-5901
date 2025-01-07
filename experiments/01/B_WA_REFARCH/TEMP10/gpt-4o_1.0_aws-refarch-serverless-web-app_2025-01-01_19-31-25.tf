terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The region to deploy resources"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "The stack name for resource identification"
  default     = "my-app"
}

variable "github_repo" {
  description = "GitHub repository for the Amplify app"
}

resource "aws_cognito_user_pool" "auth" {
  name                       = "user-pool-${var.stack_name}"
  auto_verified_attributes   = ["email"]
  alias_attributes           = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "auth_client" {
  user_pool_id             = aws_cognito_user_pool.auth.id
  name                     = "app-client-${var.stack_name}"
  generate_secret          = false
  allowed_oauth_flows      = ["code", "implicit"]
  allowed_oauth_scopes     = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "auth_domain" {
  domain      = "auth-${var.stack_name}.myapp.com"
  user_pool_id = aws_cognito_user_pool.auth.id
}

resource "aws_dynamodb_table" "todo" {
  name         = "todo-table-${var.stack_name}"
  hash_key     = "cognito-username"
  range_key    = "id"
  billing_mode = "PROVISIONED"

  read_capacity  = 5
  write_capacity = 5

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
    Name = "dynamodb-${var.stack_name}"
  }
}

resource "aws_apigatewayv2_api" "api" {
  name               = "api-${var.stack_name}"
  protocol_type      = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
  }
}

resource "aws_lambda_function" "crud_functions" {
  for_each = {
    "add-item"     = "POST /item"
    "get-item"     = "GET /item/{id}"
    "get-all"      = "GET /item"
    "update-item"  = "PUT /item/{id}"
    "complete-item" = "POST /item/{id}/done"
    "delete-item"  = "DELETE /item/{id}"
  }

  function_name = "${each.key}-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  # Assume that the source code is available in a local directory named "functions/${each.key}"
  filename         = "functions/${each.key}.zip"
  source_code_hash = filebase64sha256("functions/${each.key}.zip")
  
  role = aws_iam_role.lambda_exec.arn
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = aws_lambda_function.crud_functions
  name          = "/aws/lambda/${each.key}"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "prod"
  auto_deploy = true
}

resource "aws_apigatewayv2_authorizer" "api_authorizer" {
  api_id       = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_source = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.auth_client.id]
    issuer   = aws_cognito_user_pool.auth.endpoint
  }
}

resource "aws_amplify_app" "frontend" {
  name           = "amplify-${var.stack_name}"
  repository     = var.github_repo

  build_spec = <<EOF
version: 0.1
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

EOF
}

resource "aws_amplify_branch" "main" {
  app_id = aws_amplify_app.frontend.id
  branch_name  = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "lambda_exec" {
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

  tags = {
    Name = "lambda-role-${var.stack_name}"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = [
          aws_dynamodb_table.todo.arn,
          "${aws_dynamodb_table.todo.arn}/index/*"
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/*"
      },
      {
        Action = "cloudwatch:PutMetricData",
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api-gateway/${var.stack_name}"
  retention_in_days = 14
}

resource "aws_iam_role" "apigateway_exec" {
  name = "apigateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "apigateway-role-${var.stack_name}"
  }
}

resource "aws_iam_role_policy" "apigateway_policy" {
  name = "apigateway-policy-${var.stack_name}"
  role = aws_iam_role.apigateway_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = aws_cloudwatch_log_group.api_gateway_logs.arn
      }
    ]
  })
}

resource "aws_iam_role" "amplify_exec" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "amplify-role-${var.stack_name}"
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "amplify-policy-${var.stack_name}"
  role = aws_iam_role.amplify_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:CreateBranch",
          "amplify:UpdateBranch",
          "amplify:DeleteBranch"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.auth.id
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.auth_client.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB Table"
  value       = aws_dynamodb_table.todo.name
}

output "api_gateway_url" {
  description = "Invoke URL for the API Gateway"
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "amplify_app_id" {
  description = "ID of the Amplify App"
  value       = aws_amplify_app.frontend.id
}
