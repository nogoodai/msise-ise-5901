terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
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

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_user_pool_client" "client" {
  name                                = "${var.application_name}-${var.stack_name}-client"
  user_pool_id                        = aws_cognito_user_pool.pool.id
  explicit_auth_flows                 = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  generate_secret                     = false
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Placeholder, update with actual callback URLs
  logout_urls                         = ["http://localhost:3000/"] # Placeholder, update with actual logout URLs
  supported_identity_providers        = ["COGNITO"]
  prevent_user_existence_errors       = "ENABLED"
  refresh_token_validity             = 30 # Days
  allowed_oauth_flows_user_pool_client = true
}


resource "aws_dynamodb_table" "todo_table" {
 name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5
 server_side_encryption {
 enabled = true
 }

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
}

# Placeholder for API Gateway and Lambda functions. Implementation requires detailed API specifications and Lambda function code, which are beyond the scope of this secure infrastructure setup.

# Placeholder for Amplify.  Requires repository details.

resource "aws_amplify_app" "app" {
  name       = var.application_name
  repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token. Best practice is to store this in AWS Secrets Manager.

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
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.app.id
  branch_name = var.github_branch
  stage = "PRODUCTION"
  enable_auto_build = true
}


# Placeholder for IAM roles and policies. Requires the specification of precise permissions for each component, which depends on the specific actions they need to perform.  These will be added in a future iteration when more details are provided about the Lambda functions and their interactions with other AWS services.
