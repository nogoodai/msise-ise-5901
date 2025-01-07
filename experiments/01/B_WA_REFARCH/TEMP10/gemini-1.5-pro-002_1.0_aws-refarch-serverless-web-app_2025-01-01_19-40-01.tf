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

variable "application_name" {
  type = string
  default = "todo-app"
}

variable "environment" {
  type = string
  default = "dev"
}

variable "stack_name" {
  type = string
  default = "todo-app-stack"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.environment}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  username_attributes = ["email"]

  verification_message_template {
    default_email_options {
      access_token = "ACCESS_TOKEN"
    }
    email_message = "Your verification code is {####}"
    email_message_by_link = "Click here to verify your account: {##Click Here##}"
    email_subject = "Welcome to ${var.application_name}!"
    email_subject_by_link = "Verify your ${var.application_name} account"
    sms_message = "Your verification code is {####}"
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-cognito-user-pool"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  tags = {
    Name        = "${var.application_name}-cognito-user-pool-client"
    Environment = var.environment
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-cognito-user-pool-domain"
    Environment = var.environment
    Project     = var.application_name
  }
}


resource "aws_dynamodb_table" "main" {
 name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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

  tags = {
    Name        = "${var.application_name}-dynamodb-table"
    Environment = var.environment
    Project     = var.application_name
  }
}




# ... (API Gateway, Lambda, Amplify, IAM roles and policies will be added in the next response due to character limit)
