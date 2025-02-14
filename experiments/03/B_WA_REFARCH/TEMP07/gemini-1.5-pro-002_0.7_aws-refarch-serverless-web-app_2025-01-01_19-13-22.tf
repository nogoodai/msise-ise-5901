terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "stack_name" {
  type    = string
  default = "dev-todo-app-stack"
}

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.project_name}-user-pool-domain"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.project_name}-user-pool-client-${var.stack_name}"

 user_pool_id = aws_cognito_user_pool.main.id
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls = ["http://localhost:3000/"] # Placeholder URL
  logout_urls   = ["http://localhost:3000/"] # Placeholder URL

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_dynamodb_table" "todo_table" {
 name         = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
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

  tags = {
    Name        = "todo-table"
    Environment = var.environment
    Project     = var.project_name
  }
}


# Placeholder for API Gateway, Lambda, Amplify, and IAM resources.
# These will be implemented in the next iterations.



output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}


