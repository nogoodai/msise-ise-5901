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
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                        = aws_cognito_user_pool.main.id
  generate_secret                     = false
  explicit_auth_flows                 = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  prevent_user_existence_errors      = "ENABLED"
  allowed_oauth_flows_user_pool_client = true

  callback_urls = ["http://localhost:3000"] # Placeholder callback URL
  logout_urls   = ["http://localhost:3000"] # Placeholder logout URL
}


resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "provisioned"
  read_capacity  = 5
  write_capacity = 5
 server_side_encryption {
    enabled = true
  }

  attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  hash_key = "cognito-username"
  range_key = "id"

  tags = {
    Name        = "todo-table"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}



# Placeholder for API Gateway, Lambda, Amplify, IAM roles, etc.
# ... (Further implementation required for these components) ...


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
  value = aws_dynamodb_table.main.name
}
