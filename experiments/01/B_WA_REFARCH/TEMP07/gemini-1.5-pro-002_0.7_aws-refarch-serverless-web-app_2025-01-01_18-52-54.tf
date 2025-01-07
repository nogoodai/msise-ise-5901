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

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


# Cognito User Pool
resource "aws_cognito_user_pool" "pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.pool.id
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.pool.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls                          = ["http://localhost:3000/"] # Replace with your logout URLs
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# DynamoDB Table
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
 tags = {
   Name        = "todo-table-${var.stack_name}"
   Environment = var.stack_name
   Project     = var.application_name
 }
}


# IAM Role for API Gateway CloudWatch Logs
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
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
 tags = {
   Name        = "api-gateway-cloudwatch-role-${var.stack_name}"
   Environment = var.stack_name
   Project     = var.application_name
 }
}


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
 Resource = "*"
      },
    ]
  })
}


# API Gateway (Simplified - Requires further configuration for resources, methods, integrations)
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api-${var.stack_name}"

 tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


# Placeholder for Lambda functions and related resources (Requires detailed implementation based on specific logic)

# Amplify App
resource "aws_amplify_app" "app" {
 name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo_url
 oauth_token = var.github_oauth_token # Replace with your GitHub OAuth token
 build_spec = <<EOF
 version: 0.1
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
 EOF
 tags = {
   Name        = "${var.application_name}-amplify-${var.stack_name}"
   Environment = var.stack_name
   Project     = var.application_name
 }
}

resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.app.id
 branch_name = var.github_repo_branch
 enable_auto_build = true
 tags = {
   Name        = "${var.application_name}-amplify-branch-${var.stack_name}"
   Environment = var.stack_name
   Project     = var.application_name
 }
}



# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.todo_table.name
}


output "api_gateway_id" {
 value = aws_api_gateway_rest_api.api.id
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}



