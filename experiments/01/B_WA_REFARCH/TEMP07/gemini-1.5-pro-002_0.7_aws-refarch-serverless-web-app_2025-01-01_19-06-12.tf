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

variable "application_name" {
  type = string
  default = "todo-app"
}

variable "stack_name" {
  type = string
  default = "dev"
}

variable "github_repo_url" {
  type = string
  default = "https://github.com/your-username/your-repo" # Replace with your GitHub repository URL
}

variable "github_repo_branch" {
  type = string
  default = "main" # Replace with your GitHub branch name
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}



# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_mode = ["AUTHORIZATION_CODE", "IMPLICIT"]
 allowed_oauth_scopes = ["email", "phone", "openid"]

  generate_secret = false
}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
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

 server_side_encryption {
    enabled = true
  }

}


# IAM Role for API Gateway logging to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"
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

# IAM Policy for API Gateway logging to CloudWatch
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
        Effect = "Allow",
 Resource = "*"
      },
    ]
  })
}

# Placeholder for API Gateway and Lambda resources (to be implemented in the future)

# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
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
EOF
}

# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
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
        Effect = "Allow",
        Principal = {
 Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
}

# IAM Policy for Amplify
resource "aws_iam_role_policy" "amplify_policy" {
  name = "amplify-policy-${var.stack_name}"
 role = aws_iam_role.amplify_role.id
  policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
      {
        Action = "*",
        Effect = "Allow",
        Resource = "*"
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

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}

