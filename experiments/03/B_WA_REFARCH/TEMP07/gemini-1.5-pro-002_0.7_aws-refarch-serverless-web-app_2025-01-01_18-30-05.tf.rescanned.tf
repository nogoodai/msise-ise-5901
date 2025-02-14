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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The name of the application."
  default     = "todo-app"
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token with appropriate permissions."
  sensitive   = true
}

variable "callback_urls" {
  type        = list(string)
  description = "Callback URLs for the Cognito User Pool Client."
  default     = ["http://localhost:3000/"]
}

variable "logout_urls" {
  type        = list(string)
  description = "Logout URLs for the Cognito User Pool Client."
  default     = ["http://localhost:3000/"]
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }

  mfa_configuration = "OFF" # Consider changing to "ON" or "OPTIONAL" for production

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                      = var.callback_urls
  logout_urls                       = var.logout_urls
  supported_identity_providers      = ["COGNITO"]

    tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-domain"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Consider using PAY_PER_REQUEST for cost optimization
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
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }


}


# IAM Role for API Gateway to CloudWatch Logs
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
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}

# IAM Policy for API Gateway to CloudWatch Logs
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
        Resource = "*" # Limit resource access for improved security. Example: arn:aws:logs:*:*:log-group:/aws/apigateway/*
      },
    ]
  })
}

resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.application_name}-access-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name        = "${var.application_name}-access-analyzer"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}


# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url
  access_token = var.github_access_token
  tags = {
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}

# Amplify Branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
  # Add build settings here
    tags = {
    Name        = "${var.application_name}-${var.stack_name}-master-branch"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "cognito_user_pool_arn" {
  value       = aws_cognito_user_pool.main.arn
  description = "The ARN of the Cognito User Pool."
}


output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.main.arn
  description = "The ARN of the DynamoDB table."
}


output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

output "amplify_app_default_domain" {
  value       = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}


