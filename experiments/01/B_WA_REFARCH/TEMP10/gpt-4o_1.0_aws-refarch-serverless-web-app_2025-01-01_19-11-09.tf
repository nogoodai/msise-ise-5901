terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "stack_name" {
  default = "my-stack"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify"
}

resource "aws_cognito_user_pool" "auth" {
  name                     = "${var.stack_name}-user-pool"
  auto_verified_attributes = ["email"]
  
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  user_pool_id               = aws_cognito_user_pool.auth.id
  generate_secret            = false
  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  callback_urls              = ["https://example.com/callback"]
  logout_urls                = ["https://example.com/logout"]
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.stack_name}-cognito"
  user_pool_id = aws_cognito_user_pool.auth.id
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

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for the serverless web application"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  body = jsonencode({
    "swagger"  : "2.0",
    "info"     : {"version": "1.0", "title": "Todo API"},
    "paths"    : {
      "/item": {
        "get": {
          "x-amazon-apigateway-integration": {
            "httpMethod": "GET", "uri": module.lambda_get_item.invoke_arn, "type": "aws_proxy"
          }
        }
      }
      // Add other paths similarly
    }
    // Enable CORS here
    "x-amazon-apigateway-request-validator": "MyValidator"
  })

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "resource"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "CognitoAuthorizer"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  provider_arns          = [aws_cognito_user_pool.auth.arn]
  type                   = "COGNITO_USER_POOLS"
  identity_source        = "method.request.header.Authorization"
}

resource "aws_lambda_function" "lambda_get_item" {
  filename         = "path/to/lambda.zip"
  function_name    = "${var.stack_name}-get-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo.name
    }
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-exec-role"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.stack_name}-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:*"],
        Effect   = "Allow",
        Resource = [aws_dynamodb_table.todo.arn]
      },
      {
        Action   = ["logs:*"],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_get_item.function_name}"
  retention_in_days = 7
}

resource "aws_appsync_graphql_api" "amplify" {
  name                = "${var.stack_name}-amplify"
  authentication_type = "AMAZON_COGNITO_USER_POOLS"

  user_pool_config {
    user_pool_id = aws_cognito_user_pool.auth.id
  }

  tags = {
    Name        = "${var.stack_name}-amplify"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_appsync_datasource" "dynamo_source" {
  api_id            = aws_appsync_graphql_api.amplify.id
  name              = "DynamoDatasource"
  type              = "AMAZON_DYNAMODB"
  dynamodb_config {
    table_name = aws_dynamodb_table.todo.name
    use_caller_credentials = true
  }
}

output "user_pool_id" {
  value = aws_cognito_user_pool.auth.id
}

output "api_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "lambda_function_arn" {
  value = aws_lambda_function.lambda_get_item.arn
}
