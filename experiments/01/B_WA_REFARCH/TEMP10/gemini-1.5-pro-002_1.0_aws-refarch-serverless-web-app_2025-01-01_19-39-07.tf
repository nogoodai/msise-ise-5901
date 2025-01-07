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

variable "project_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "stack_name" {
  type = string
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }
  tags = {
    Name        = "${var.project_name}-user-pool-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.project_name}-user-pool-client-${var.stack_name}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                    = false
 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
 refresh_token_validity              = 30
  callback_urls                      = ["http://localhost:3000/"] # Update with your callback URL
  logout_urls                        = ["http://localhost:3000/"] # Update with your logout URL
  tags = {
    Name        = "${var.project_name}-user-pool-client-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }

}

resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
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
    Environment = var.environment
    Project     = var.project_name
  }
}




# Placeholder for API Gateway, Lambda, Amplify, IAM Roles, and Policies
# These resources will require more detailed configuration based on specific function requirements and Amplify settings.


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

