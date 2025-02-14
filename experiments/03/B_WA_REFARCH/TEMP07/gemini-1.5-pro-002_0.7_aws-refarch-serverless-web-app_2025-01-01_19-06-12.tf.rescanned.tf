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
  default     = "us-west-2"
}

variable "application_name" {
  type        = string
  description = "The name of the application."
  default     = "todo-app"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack (e.g., dev, prod)."
  default     = "dev"
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
  default     = "https://github.com/your-username/your-repo"
}

variable "github_repo_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "main"
}


variable "github_access_token" {
  type        = string
  description = "GitHub personal access token with appropriate permissions."
  sensitive   = true
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
 tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
  mfa_configuration = "OFF" # Enable MFA for enhanced security

  password_policy {
    minimum_length     = 8 # Increased minimum length
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true # Require numbers in password
    require_symbols   = true # Require symbols in password
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
 billing_mode = "PAY_PER_REQUEST" # Use on-demand billing mode
 # Using on-demand eliminates the need to define read and write capacity units, which makes your application more scalable and cost-effective.


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
 point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
 Project     = var.application_name
  }

}



# IAM Role for API Gateway logging to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"
 tags = {
    Name        = "api-gateway-cloudwatch-logs-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
 }
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
 Resource = aws_cloudwatch_log_group.api_gateway.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "/api-gateway/${var.application_name}-${var.stack_name}"

  retention_in_days = 30
}
# Placeholder for API Gateway and Lambda resources (to be implemented in the future)

# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url
  access_token = var.github_access_token
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

 tags = {
    Name        = "amplify-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Policy for Amplify
resource "aws_iam_role_policy" "amplify_policy" {
  name = "amplify-policy-${var.stack_name}"
 role = aws_iam_role.amplify_role.id
  policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "cloudfront:CreateInvalidation"

 ],
        Effect   = "Allow",
        Resource = ["arn:aws:s3:::${var.application_name}-${var.stack_name}", "arn:aws:s3:::${var.application_name}-${var.stack_name}/*"] # Limit access to specific buckets
      },
    ]
  })

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

output "dynamodb_table_name" {
 value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
  value       = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}


