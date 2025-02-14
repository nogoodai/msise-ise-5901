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

variable "stack_name" {
  type        = string
  description = "The name of the stack. Used as a prefix for resource names."
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}


variable "tags" {
  type        = map(string)
  description = "A map of tags to apply to all resources."
  default = {
    Environment = "dev",
    Project     = "todo-app"
  }

}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 12
 require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  mfa_configuration = "OFF" # Consider changing to "ON" or "OPTIONAL" for production

  tags = var.tags
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                         = "${var.stack_name}-user-pool-client"
  user_pool_id                = aws_cognito_user_pool.main.id
  explicit_auth_flows         = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  generate_secret              = false
  supported_identity_providers = ["COGNITO"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Replace with your frontend callback URL
  logout_urls = ["http://localhost:3000/"] # Replace with your frontend logout URL

  prevent_user_existence_errors = "ENABLED"


  tags = var.tags
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_id.suffix.hex}"
 user_pool_id = aws_cognito_user_pool.main.id

  tags = var.tags
}

resource "random_id" "suffix" {
  byte_length = 4
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

 server_side_encryption {
    enabled = true
  }
 point_in_time_recovery {
    enabled = true
  }

  tags = var.tags
}

# IAM Role for API Gateway to log to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-api-gateway-cloudwatch-role"

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

  tags = var.tags

}


# IAM Policy for API Gateway to log to CloudWatch
resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cloudwatch-policy"
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
 Resource = "*" #  Consider restricting the resource to specific log groups.
 }
    ]
 })


  tags = var.tags
}


resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.stack_name}-analyzer"
 type        = "ACCOUNT"

 tags = var.tags
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

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "The domain of the Cognito User Pool."
}

output "access_analyzer_arn" {
 value = aws_accessanalyzer_analyzer.main.arn
 description = "The ARN of the Access Analyzer."
}
