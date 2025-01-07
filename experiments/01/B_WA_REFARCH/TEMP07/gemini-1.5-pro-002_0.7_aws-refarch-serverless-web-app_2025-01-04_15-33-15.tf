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



# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes = ["email"]

  verification_message_template {
    default_email_options {
      email_message = "Your verification code is {####}"
      email_subject = "Welcome to ${var.application_name}"
    }
  }

  password_policy {
    minimum_length                   = 6
    require_lowercase               = true
    require_numbers                 = false
    require_symbols                 = false
    require_uppercase               = true
    temporary_password_validity_days = 7
  }

  auto_verified_attributes = ["email"]
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls        = ["http://localhost:3000/"] # Placeholder, update with actual callback URL
  logout_urls          = ["http://localhost:3000/"] # Placeholder, update with actual logout URL
  supported_identity_providers = ["COGNITO"]
  prevent_user_existence_errors = "ENABLED"
 refresh_token_validity = 30

}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# DynamoDB Table
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

}



# IAM Role for API Gateway logging
resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = "1",
      },
    ]
  })
}


# IAM Policy for API Gateway logging
resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {

  name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*",
        Effect   = "Allow",
      },
    ]
  })
}


# Placeholder for API Gateway - Needs more details for full implementation
# resource "aws_api_gateway_rest_api" "main" {
#   name        = "${var.application_name}-${var.stack_name}-api"
# }


# Placeholder for Lambda Functions - Needs more details for full implementation
# resource "aws_lambda_function" "example" {
#   function_name = "my-lambda-function"
#   # ... other configuration ...
# }

# Amplify App
resource "aws_amplify_app" "main" {
  name = "${var.application_name}-${var.stack_name}-amplify-app"


  repository = var.github_repo_url

  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token

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
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  name        = var.github_branch
  enable_auto_build = true
}




# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "amplify.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = "1",
      },
    ]
  })
}

# IAM Policy for Amplify - Provide specific permissions as needed
resource "aws_iam_role_policy" "amplify_policy" {
  name = "amplify-policy-${var.stack_name}"
  role = aws_iam_role.amplify_role.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "*", # Replace with specific permissions
        Resource = "*", # Replace with specific resources
        Effect   = "Allow",
      },
    ]
  })
}


# Outputs
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

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}



