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
  description = "The AWS region to deploy resources"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "The stack name used for naming resources"
  default     = "my-app"
}

variable "amplify_source_repo" {
  description = "The GitHub repository for Amplify app source"
}

resource "aws_cognito_user_pool" "auth" {
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

resource "aws_cognito_user_pool_client" "auth_client" {
  name                      = "app-client-${var.stack_name}"
  user_pool_id              = aws_cognito_user_pool.auth.id
  generate_secret           = false
  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]
  callback_urls             = ["https://example.com/callback"]
  logout_urls               = ["https://example.com/logout"]
}

resource "aws_cognito_user_pool_domain" "auth_domain" {
  domain      = "${var.stack_name}-auth-domain"
  user_pool_id = aws_cognito_user_pool.auth.id
}

resource "aws_dynamodb_table" "todo" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key     = "cognito-username"
  range_key    = "id"

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
  name          = "${var.stack_name}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  }
}

resource "aws_lambda_function" "crud_functions" {
  count       = 6
  filename    = "path_to_lambda_package.zip"
  function_name = "${var.stack_name}-${tolist(["add", "get", "get_all", "update", "complete", "delete"])[count.index]}"
  handler     = "index.handler"
  runtime     = "nodejs12.x"
  timeout     = 60
  memory_size = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_permission" "apigateway" {
  count         = 6
  statement_id  = "AllowAPIGatewayInvoke${count.index}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud_functions[count.index].function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  count      = 6
  api_id     = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.crud_functions[count.index].invoke_arn
}

resource "aws_apigatewayv2_route" "lambda_routes" {
  count      = 6
  api_id     = aws_apigatewayv2_api.api.id
  route_key  = tolist(["POST /item", "GET /item/{id}", "GET /item", "PUT /item/{id}", "POST /item/{id}/done", "DELETE /item/{id}"])[count.index]
  target     = aws_apigatewayv2_integration.lambda_integration[count.index].id
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id   = aws_apigatewayv2_api.api.id
  name     = "prod"
  auto_deploy = true
}

resource "aws_appsync_graphql_api" "amplify_app" {
  name          = "${var.stack_name}-amplify-app"
  authentication_type = "API_KEY"
}

resource "aws_appsync_datasource" "amplify_source" {
  api_id = aws_appsync_graphql_api.amplify_app.id
  name   = "GitHubSource"
  type   = "HTTP"
}

resource "aws_iam_role" "lambda_exec_role" {
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

  inline_policy {
    name = "DynamoDBPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo.arn
      }]
    })
  }
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

  inline_policy {
    name = "CloudWatchLogsPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      }]
    })
  }
}

resource "aws_amplify_app" "amplify_frontend" {
  name = "${var.stack_name}-amplify-app"
  repository = var.amplify_source_repo
  oauth_token = sensitive(var.github_oauth_token)
  auto_branch_creation_config {
    patterns = ["master"]
  }
}

output "user_pool_id" {
  value = aws_cognito_user_pool.auth.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_frontend.id
}
