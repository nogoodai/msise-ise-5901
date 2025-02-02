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

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

 email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
 }


  verification_message_template {
    default_email_options {
      source_arn = "arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:identity/ses.amazonaws.com"
    }
  }
}

data "aws_caller_identity" "current" {}


resource "aws_cognito_user_pool_domain" "main" {
 domain      = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "client" {
  name = "${var.stack_name}-client"

  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                = ["phone", "email", "openid"]

  generate_secret = false

  callback_urls = ["http://localhost:3000/"] # Placeholder, update with actual frontend URL
  logout_urls   = ["http://localhost:3000/"] # Placeholder, update with actual frontend URL
}


resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
 read_capacity = 5
  write_capacity = 5
  hash_key       = "cognito-username"
  range_key       = "id"

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
    Environment = "production"
  }
}


resource "aws_amplify_app" "main" {
  name       = "${var.stack_name}-amplify-app"
  repository = var.github_repo_url

  build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
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
EOF
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your actual GitHub Personal Access Token.  This is insecure and should not be done in production.  Use OIDC instead.
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

}

# Placeholder for API Gateway and Lambda. This section needs further details from the user on the required API endpoints and integrations.


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}
