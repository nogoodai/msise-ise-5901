terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-west-2"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., dev, prod)."
  default     = "dev"
}

variable "project_name" {
  type        = string
  description = "The project name."
  default     = "todo-app"
}

variable "stack_name" {
  type        = string
  description = "The stack name."
  default     = "todo-app-stack"
}

variable "cognito_domain_prefix" {
  type        = string
  description = "The Cognito domain prefix."
  default     = "todo-app-${var.stack_name}"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.environment}"

  password_policy {
    minimum_length = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }
  mfa_configuration = "OFF" # Consider enforcing MFA for production environments

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.project_name}-user-pool-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.project_name}-user-pool-client-${var.environment}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  explicit_auth_flows               = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  generate_secret                   = false
  callback_urls                     = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls                       = ["http://localhost:3000/"] # Replace with your logout URLs

  prevent_user_existence_errors = "ENABLED"


}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
 name         = "todo-table-${var.stack_name}"
 billing_mode = "PAY_PER_REQUEST" # Consider using PAY_PER_REQUEST for cost optimization
 read_capacity = 5
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

 point_in_time_recovery {
    enabled = true
 }

 tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
 }
}

resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "todo-app-analyzer"
 type = "ACCOUNT"

 tags = {
    Name = "todo-app-analyzer"
    Environment = var.environment
    Project = var.project_name

 }
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}


