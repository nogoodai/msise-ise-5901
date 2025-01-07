terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "stack_name" {
  description = "Name of the application stack"
  default     = "myapp"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify"
  default     = "https://github.com/example/repo"
}

resource "aws_cognito_user_pool" "app_user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

resource "aws_cognito_user_pool_domain" "app_domain" {
  domain      = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
}

resource "aws_cognito_user_pool_client" "app_user_pool_client" {
  name         = "app-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_dynamodb_table" "todo_table" {
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

resource "aws_apigatewayv2_api" "app_api" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.app_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.app_user_pool_client.id]
    issuer   = aws_cognito_user_pool.app_user_pool.endpoint
  }
}

resource "aws_apigatewayv2_stage" "prod_stage" {
  api_id      = aws_apigatewayv2_api.app_api.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_log_group.arn
    format          = "$context.requestId"
  }
}

resource "aws_cloudwatch_log_group" "api_gw_log_group" {
  name = "/aws/apigateway/${aws_apigatewayv2_api.app_api.name}"
}

resource "aws_apigatewayv2_route" "add_item" {
  api_id    = aws_apigatewayv2_api.app_api.id
  route_key = "POST /item"
  target    = "integrations/${aws_lambda_function.add_item_integration.id}"
}

resource "aws_lambda_function" "add_item_function" {
  function_name = "add-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_permission" "api_gw_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item_function.arn
  principal     = "apigateway.amazonaws.com"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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

  inline_policy {
    name = "dynamodb-crud-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      }]
    })
  }
}

resource "aws_amplify_app" "app" {
  name = "amplify-app-${var.stack_name}"
  repository = var.github_repo

  build_spec = <<-EOT
    version: 0.1
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
    EOT
}

resource "aws_amplify_branch" "master_branch" {
  app_id = aws_amplify_app.app.id
  branch_name = "master"
  enable_auto_build = true
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.app_user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_apigatewayv2_stage.prod_stage.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}
