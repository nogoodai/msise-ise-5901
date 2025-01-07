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

variable "stack_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]

  allowed_oauth_scopes = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Placeholder, update with your frontend URL
  logout_urls          = ["http://localhost:3000/"] # Placeholder, update with your frontend URL

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  refresh_token_validity = 30

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

}

# Placeholder for Lambda Functions, API Gateway, Amplify, IAM Roles and Policies
# The detailed implementation for these resources requires specific function code and build specifications.
# The following is a skeletal representation of these components, and needs to be populated further.


resource "aws_iam_role" "api_gateway_role" {
 name = "api-gateway-cloudwatch-role-${var.stack_name}"
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


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
 role = aws_iam_role.api_gateway_role.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
 Effect = "Allow",
 Resource = "*"
      },
    ]
  })

}




output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}


