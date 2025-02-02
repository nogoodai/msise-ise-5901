terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
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


resource "aws_cognito_user_pool" "this" {
  name                     = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  schema {
    attribute_data_type = "String"
    developer_only_attribute = false
    mutable = true
    name = "email"
    required = true
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
}


resource "aws_cognito_user_pool_client" "this" {
  name            = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id    = aws_cognito_user_pool.this.id
  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                      = ["http://localhost:3000/"] # Placeholder, update with actual callback URL
  logout_urls                         = ["http://localhost:3000/"] # Placeholder, update with actual logout URL

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${var.stack_name}"
 server_side_encryption {
    enabled = true
  }
  billing_mode = "PROVISIONED"
  read_capacity = 5
  write_capacity = 5
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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


# Placeholder for API Gateway and Lambda functions. Implementation details would require more specific API definitions and Lambda function code.


resource "aws_amplify_app" "this" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url
  access_token = var.github_access_token # Requires a GitHub access token
 build_spec = <<-EOT
version: 0.1
frontend:
  phases:
    install:
      commands:
        - npm install
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
EOT

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

variable "github_access_token" {}

resource "aws_amplify_branch" "this" {
 app_id = aws_amplify_app.this.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}
