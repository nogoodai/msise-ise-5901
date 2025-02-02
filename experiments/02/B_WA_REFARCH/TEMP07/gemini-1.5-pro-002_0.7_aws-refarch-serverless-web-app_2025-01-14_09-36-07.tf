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
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}



# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                       = aws_cognito_user_pool.main.id
  explicit_auth_flows                = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret                    = false
  prevent_user_existence_errors      = "ENABLED"
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                      = ["http://localhost:3000/"] # Placeholder, update with actual callback URL
  logout_urls                         = ["http://localhost:3000/"] # Placeholder, update with actual logout URL
  supported_identity_providers       = ["COGNITO"]

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

 tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}


# IAM Role for API Gateway Logging
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
        Sid    = ""
      },
    ]
  })
}


# IAM Policy for API Gateway Logging
resource "aws_iam_policy" "api_gateway_cloudwatch_logs_policy" {
 name = "api-gateway-cloudwatch-logs-${var.stack_name}"
 policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
 Resource = "*"
      },
    ]
  })


}

# Attach IAM Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs_attachment" {
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_logs_policy.arn
  role       = aws_iam_role.api_gateway_cloudwatch_logs_role.name
}


# (Simplified) API Gateway REST API - Replace with your actual API definition
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
}

# Placeholder for Lambda functions and their integration with API Gateway
#  - You'll need to define Lambda functions and resources,
#  - methods, integrations, and authorizers within the API Gateway.


resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"
 assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
 Principal = {
          Service = "lambda.amazonaws.com"
        },
 Effect = "Allow",
        Sid    = ""
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy-${var.stack_name}"
 policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
 {
 Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
 "dynamodb:PutItem",
          "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchWriteItem",
 "dynamodb:BatchGetItem"
 ],
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Effect = "Allow",
 Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
 ],
 Resource = "*"
      }
    ]
  })
}



resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
 role       = aws_iam_role.lambda_role.name
}


# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token
  build_spec = <<EOF
version: 0.1
frontend:
 phases:
 install:
    commands:
      - yarn install
 build:
 commands:
 - yarn build
 artifacts:
 baseDirectory: build
 files:
 - '**/*'
cache:
 paths:
      - node_modules/**/*
EOF

}

# Amplify Branch - Auto build enabled
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
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

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


