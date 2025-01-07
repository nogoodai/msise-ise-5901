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

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "cognito-username"
    type = "S"
  }
  hash_key = "cognito-username"

  attribute {
    name = "id"
    type = "S"
  }
  range_key = "id"

 server_side_encryption {
    enabled = true
  }
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "Serverless Todo App API"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id  = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# Example Lambda function (replace with actual functions and API Gateway integrations)
resource "aws_lambda_function" "example" {
  function_name = "${var.stack_name}-example-function"
  runtime = "nodejs12.x"
  handler = "index.handler"
  memory_size = 1024
  timeout = 60
  # ... (add code, environment variables, IAM role, etc.)
}


resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo_url
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
 # ... (add build spec)
}


# Example IAM role (replace with roles for API Gateway, Lambda, and Amplify)
resource "aws_iam_role" "example" {
  name = "${var.stack_name}-example-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}


# Outputs (add more as needed)
output "api_gateway_url" {
 value = aws_api_gateway_rest_api.main.id
}

