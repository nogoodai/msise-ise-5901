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
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources in."
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack."

}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The application's name."
}

variable "github_repo_url" {
  type        = string
  description = "URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  default     = "master"
  description = "Branch of the GitHub repository to use."
}

variable "github_oauth_token" {
  type        = string
  sensitive   = true
  description = "GitHub OAuth token with appropriate permissions for Amplify."
}

# Cognito User Pool
resource "aws_cognito_user_pool" "pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }

 mfa_configuration = "OFF" # Consider changing to 'ON' or 'OPTIONAL' in production


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
  generate_secret                      = true # Set to true for enhanced security. Manage the secret securely.
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
 billing_mode   = "PAY_PER_REQUEST" # Consider using PAY_PER_REQUEST for cost optimization
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

 point_in_time_recovery {
    enabled = true
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
        Resource = "*" # Restrict this to specific log groups for least privilege
      },
    ]
  })
}

resource "aws_accessanalyzer_analyzer" "analyzer" {
  analyzer_name = "access-analyzer-${var.stack_name}"
  type          = "ACCOUNT"
  tags = {
    Name        = "access-analyzer-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
 }
}



# API Gateway (Simplified - Requires further configuration for resources, methods, integrations)
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api-${var.stack_name}"
 minimum_compression_size = 0


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
  value       = aws_cognito_user_pool.pool.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.client.id
  description = "The ID of the Cognito User Pool Client."
}

output "cognito_user_pool_client_secret" {
  value       = aws_cognito_user_pool_client.client.client_secret
  description = "The secret of the Cognito User Pool Client."
  sensitive   = true
}

output "dynamodb_table_name" {
 value       = aws_dynamodb_table.todo_table.name
 description = "The name of the DynamoDB table."
}


output "api_gateway_id" {
 value       = aws_api_gateway_rest_api.api.id
 description = "The ID of the API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.app.id
  description = "The ID of the Amplify app."
}


