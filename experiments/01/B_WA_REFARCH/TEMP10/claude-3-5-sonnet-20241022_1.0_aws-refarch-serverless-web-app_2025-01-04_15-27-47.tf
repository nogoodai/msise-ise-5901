terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  default = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack/environment"
  default     = "prod"
}

variable "github_repository" {
  description = "GitHub repository URL for Amplify"
}

variable "github_token" {
  description = "GitHub personal access token"
  sensitive   = true
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verify_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Environment = var.stack_name
    Terraform   = "true"
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  
  callback_urls = ["http://localhost:3000"]
  logout_urls   = ["http://localhost:3000"]
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "cognito-username"
  range_key      = "id"

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
    Environment = var.stack_name
    Terraform   = "true"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name = "api-${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito-authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "main" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = "prod"
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"

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

# Lambda DynamoDB Policy
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

# Lambda CloudWatch Policy
resource "aws_iam_role_policy" "lambda_cloudwatch" {
  name = "lambda-cloudwatch-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Functions
locals {
  lambda_functions = {
    add_item = {
      name   = "add-item"
      method = "POST"
      path   = "/item"
    }
    get_item = {
      name   = "get-item"
      method = "GET"
      path   = "/item/{id}"
    }
    get_all_items = {
      name   = "get-all-items"
      method = "GET"
      path   = "/item"
    }
    update_item = {
      name   = "update-item"
      method = "PUT"
      path   = "/item/{id}"
    }
    complete_item = {
      name   = "complete-item"
      method = "POST"
      path   = "/item/{id}/done"
    }
    delete_item = {
      name   = "delete-item"
      method = "DELETE"
      path   = "/item/{id}"
    }
  }
}

resource "aws_lambda_function" "functions" {
  for_each = local.lambda_functions

  filename         = "lambda.zip"
  function_name    = "${each.value.name}-${var.stack_name}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs12.x"
  memory_size     = 1024
  timeout         = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Environment = var.stack_name
    Terraform   = "true"
  }
}

# Amplify App
resource "aws_amplify_app" "main" {
  name         = "frontend-${var.stack_name}"
  repository   = var.github_repository
  access_token = var.github_token

  build_spec = <<-EOT
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
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  custom_rule {
    source = "/<*>"
    status = "404-200"
    target = "/index.html"
  }
}

# Amplify Branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
  
  framework   = "React"
  stage       = "PRODUCTION"

  enable_auto_build = true
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "api_gateway_url" {
  value = "${aws_api_gateway_rest_api.main.execution_arn}/prod"
}

output "amplify_app_url" {
  value = "https://${aws_amplify_branch.master.branch_name}.${aws_amplify_app.main.default_domain}"
}
