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
  default = "us-west-2"
}

variable "project_name" {
  type    = string
  default = "serverless-todo"
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

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
 email_verification_subject = "Verify Your Email for ${var.project_name}"
  email_verification_message = "Your verification code is {####}"
  sms_verification_message = "Your verification code is {####}"

  tags = {
    Name        = "${var.project_name}-user-pool-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

 allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls        = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls          = ["http://localhost:3000/"] # Placeholder, update as needed
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "${var.project_name}-user-pool-client-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}




resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
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
 Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
 Project     = var.project_name
  }
}

# (API Gateway, Lambda, Amplify, IAM Roles, and other components will be implemented in a future iteration due to the character limit. These will be added when provided with more context in another interaction)
# Example of IAM role for Lambda

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
 {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
 }
      },
    ]
  })

  tags = {
    Name        = "${var.project_name}-lambda-role-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}



