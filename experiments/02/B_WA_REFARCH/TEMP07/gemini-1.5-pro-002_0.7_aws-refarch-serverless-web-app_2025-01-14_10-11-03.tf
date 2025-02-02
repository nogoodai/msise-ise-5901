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
  default = "master"
}


resource "aws_cognito_user_pool" "pool" {
  name = "${var.stack_name}-user-pool"
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }
}



resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls        = ["http://localhost:3000/"] # Placeholder, replace with your actual callback URL
  logout_urls          = ["http://localhost:3000/"] # Placeholder, replace with your actual logout URL
  supported_identity_providers = ["COGNITO"]
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
}


resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api_gateway_cw_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
 Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

}

resource "aws_iam_role_policy" "api_gateway_cw_policy" {
  name = "api_gateway_cw_policy_${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_role.id


 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
 Resource = "*"
      },
    ]
  })


}



resource "aws_amplify_app" "app" {
  name       = var.stack_name
  repository = var.github_repo_url
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
    baseDirectory: /build
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
  enable_auto_build = true
}


# Placeholder for API Gateway and Lambda resources - these require more detailed configuration based on the specific API endpoints and logic


output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.pool.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "amplify_app_id" {
 value = aws_amplify_app.app.id
}

output "cognito_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}
