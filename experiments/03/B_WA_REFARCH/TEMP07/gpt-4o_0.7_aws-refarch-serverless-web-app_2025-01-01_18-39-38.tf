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
  description = "The AWS region to deploy resources in"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Application stack name"
  default     = "my-app"
}

variable "project_name" {
  description = "Project name for tagging purposes"
  default     = "serverless-webapp"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the custom domain in Cognito User Pool"
  default     = "myapp"
}

variable "github_repository" {
  description = "GitHub repository for Amplify source code"
}

resource "aws_cognito_user_pool" "app_user_pool" {
  name = "${var.project_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "app_user_pool_client" {
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
  name         = "${var.project_name}-user-pool-client"

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "openid", "phone"]
  generate_secret            = false
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "app_user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
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

  billing_mode = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "app_api" {
  name        = "${var.project_name}-api"
  description = "API for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.app_api.id
  parent_id   = aws_api_gateway_rest_api.app_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.app_api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_user_pool_authorizer.id
}

resource "aws_api_gateway_authorizer" "cognito_user_pool_authorizer" {
  name         = "${var.project_name}-authorizer"
  rest_api_id  = aws_api_gateway_rest_api.app_api.id
  provider_arns = [aws_cognito_user_pool.app_user_pool.arn]
  type         = "COGNITO_USER_POOLS"
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-add-item"
  handler       = "add_item.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "${var.project_name}-add-item"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-lambda-exec-role"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  name   = "${var.project_name}-lambda-exec-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:*",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "amplify_app" {
  name               = "${var.project_name}-amplify-app"
  repository         = var.github_repository
  oauth_token        = var.github_oauth_token

  environment_variables = {
    _LIVE_UPDATES = "true"
  }

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

  tags = {
    Name        = "${var.project_name}-amplify-app"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id   = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.project_name}-amplify-branch"
    Environment = "production"
    Project     = var.project_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.app_user_pool.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.app_api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
