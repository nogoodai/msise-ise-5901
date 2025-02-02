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

variable "github_branch_name" {
 type = string
 default = "main"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

 email_verification_message = "Your verification code is {####}"
 email_verification_subject = "Verify your email address"

 verification_message_template {
    default_email_options {
      email_message = "Your verification code is {####}"
      email_subject = "Verify your email address"
    }
  }

 auto_verified_attributes = ["email"]
}


resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.main.id

 allowed_oauth_flows_user_pool_client = true
 allowed_oauth_flows                  = ["authorization_code", "implicit"]
 allowed_oauth_scopes                = ["email", "phone", "openid"]

 generate_secret = false

  callback_urls        = ["http://localhost:3000/"] # Placeholder, update with actual callback URL
  logout_urls         = ["http://localhost:3000/"] # Placeholder, update with actual logout URL

 refresh_token_validity = 30
}


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
    Environment = var.stack_name
    Project     = var.application_name
 }
}


resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
 {
        Action = "sts:AssumeRole"
        Effect = "Allow"
 Principal = {
          Service = "apigateway.amazonaws.com"
 }
      },
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_cw_policy" {
  name = "api-gateway-cw-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
 ]
 Effect   = "Allow"
 Resource = "*"
      },
    ]
  })
}

# Placeholder for API Gateway - detailed configuration requires OpenAPI/Swagger definition
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
 description = "API Gateway for ${var.application_name}"

 endpoint_configuration {
    types = ["REGIONAL"]
 }
}

# Placeholder for Lambda functions - requires function code and specific configurations
resource "aws_lambda_function" "example_function" {
 # ... (Lambda function configuration)
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
 repository = var.github_repo_url

  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with a secure way to manage this token
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
     baseDirectory: /dist
     files:
       - '**/*'
   cache:
     paths:
       - node_modules/**/*
EOF
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch_name
  enable_auto_build = true
}

# IAM role and policy for Amplify
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
      }
    ]
  })
}

resource "aws_iam_role_policy" "amplify_policy" {
 name = "amplify-policy-${var.stack_name}"
 role = aws_iam_role.amplify_role.id

 policy = jsonencode({
    Version = "2012-10-17",
 Statement = [
      {
        Effect = "Allow",
        Action = [
 "amplify:*"
 ],
        Resource = "*"
 }
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

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}
