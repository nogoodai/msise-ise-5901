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
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
  }
  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "production"
    Project     = var.application_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                     = ["http://localhost:3000/"] # Placeholder, update with actual callback URLs
  logout_urls                       = ["http://localhost:3000/"] # Placeholder, update with actual logout URLs

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = var.application_name
  }
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


# IAM Role for API Gateway logging
resource "aws_iam_role" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Sid    = "",
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "api-gateway-cloudwatch-logs-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

# IAM Policy for API Gateway logging
resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs.id
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:GetLogEvents",
        "logs:FilterLogEvents"
      ],
      Resource = "*"
    }]
  })
}

# API Gateway


# Lambda Functions (Placeholder - needs actual code deployment)
# Example for Add Item function:
resource "aws_lambda_function" "add_item" {
 # ... (Lambda function configuration, including code deployment) ...

  tags = {
    Name        = "add-item-lambda-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

# ... (Similar resources for other Lambda functions) ...


# Amplify App
resource "aws_amplify_app" "main" {
  name       = var.application_name
 repository = var.github_repo
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token
  build_spec = <<-EOT
version: 0.1
frontend:
  phases:
    preBuild:
      npm ci
    build:
      npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOT
  tags = {
    Name        = var.application_name
    Environment = "production"
    Project     = var.application_name
  }

}


# Amplify Branch (auto-build enabled)
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

  tags = {
        Name        = "${var.application_name}-master-branch"
    Environment = "production"
    Project     = var.application_name
  }
}

# IAM Role for Amplify
# ... (Amplify IAM role and policy configuration) ...

# IAM Role and Policies for Lambda functions
# ... (Lambda IAM role and policy configuration for DynamoDB and CloudWatch) ...

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

# ... (Other outputs) ...
