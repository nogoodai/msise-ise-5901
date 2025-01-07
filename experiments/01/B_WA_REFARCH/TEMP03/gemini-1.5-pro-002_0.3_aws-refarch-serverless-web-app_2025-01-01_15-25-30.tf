terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type = string
}

variable "application_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes = ["email"]

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

  password_policy {
    minimum_length                   = 6
    require_lowercase               = true
    require_numbers                 = false
    require_symbols                 = false
    require_uppercase               = true
    temporary_password_validity_days = 7
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls          = ["http://localhost:3000/"] # Replace with your logout URLs
  supported_identity_providers = ["COGNITO"]

  prevent_user_existence_errors = "ENABLED"
}

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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}



resource "aws_api_gateway_rest_api" "api" {
  name = "${var.application_name}-${var.stack_name}-api"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_amplify_app" "app" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url

  build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.application_name
  }

}

resource "aws_amplify_branch" "master" {
  app_id           = aws_amplify_app.app.id
  branch_name      = var.github_repo_branch
  enable_auto_build = true
}


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.api.id
}

output "amplify_app_id" {
 value = aws_amplify_app.app.id
}


