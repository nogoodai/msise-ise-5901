terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Stack name suffix for resource naming"
  default     = "dev"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  default     = "user/repo"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito domain"
  default     = "app-stack-dev"
}

variable "environment" {
  description = "Deployment environment"
  default     = "production"
}

resource "aws_cognito_user_pool" "user_pool" {
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

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = var.environment
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "client-${var.stack_name}"

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "client-${var.stack_name}"
    Environment = var.environment
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain      = var.cognito_domain_prefix
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "api-gateway-${var.stack_name}"
  description = "API Gateway for serverless web application"

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = var.environment
    Project     = "serverless-web-app"
  }

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  name         = "cognito-authorizer"
  rest_api_id  = aws_api_gateway_rest_api.api_gateway.id
  type         = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_resource" "api_resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"

  depends_on = [aws_api_gateway_authorizer.cognito]
}

resource "aws_api_gateway_method" "api_method" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.api_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-function-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_exec.arn

  tags = {
    Name        = "add-item-function-${var.stack_name}"
    Environment = var.environment
    Project     = "serverless-web-app"
  }

  # Assume the code is uploaded to an S3 bucket or another source like ECR. This section is placeholder.
  # code {
  #   s3_bucket = "your-bucket-name"
  #   s3_key    = "your-code.zip"
  # }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role-${var.stack_name}"

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

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = var.environment
    Project     = "serverless-web-app"
  }
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
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_amplify_app" "amplify_app" {
  name  = "amplify-app-${var.stack_name}"
  repository = "https://github.com/${var.github_repo}"

  oauth_token = var.github_token  // OAuth Token to be added.

  environment_variables = {
    _LIVE_UPDATES = "disabled"
  }

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.environment
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-log-role-${var.stack_name}"

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

  tags = {
    Name        = "api-gateway-log-role-${var.stack_name}"
    Environment = var.environment
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "api-gateway-log-policy-${var.stack_name}"
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

output "api_gateway_url" {
  description = "Base URL for the API Gateway"
  value       = aws_api_gateway_rest_api.api_gateway.execution_arn
}

output "amplify_app_id" {
  description = "Amplify App ID"
  value       = aws_amplify_app.amplify_app.id
}
