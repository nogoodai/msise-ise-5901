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
  default = "us-east-1"
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "stack_name" {
  type = string
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"
  mfa_configuration           = "OFF"
  sms_authentication_message  = "Your verification code is {####}"
  sms_verification_message   = "Your verification code is {####}"

  password_policy {
    minimum_length                   = 6
    require_lowercase               = true
    require_numbers                 = false
    require_symbols                 = false
    require_uppercase               = true
    temporary_password_validity_days = 7
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                 = true
    name                    = "email"
    required                = true

    string_attribute_constraints {
      max_length = "2048"
      min_length = "0"
    }
  }

  username_attributes = ["email"]

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Stack       = var.stack_name
 Name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
  user_pool_id                        = aws_cognito_user_pool.main.id
  generate_secret                     = false
  explicit_auth_flows                 = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  allowed_oauth_flows                 = ["implicit", "authorization_code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["phone", "email", "openid"]
  callback_urls = ["http://localhost:3000/"] # Replace with your actual callback URLs
  logout_urls = ["http://localhost:3000/"] # Replace with your actual logout URLs

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Stack       = var.stack_name
 Name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"

  }

}



resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.environment}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "main" {
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
    Environment = var.environment
    Project     = var.project_name
    Stack       = var.stack_name
 Name = "todo-table-${var.stack_name}"

  }


}


# Placeholder for API Gateway, Lambda, Amplify, IAM, and Monitoring. These will be expanded in future iterations.



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

