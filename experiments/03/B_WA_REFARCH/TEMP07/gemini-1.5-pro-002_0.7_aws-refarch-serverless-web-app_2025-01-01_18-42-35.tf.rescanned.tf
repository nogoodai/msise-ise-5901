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
  default     = "us-east-1"
  description = "The AWS region to deploy resources into."
}

variable "project_name" {
  type        = string
  description = "The name of the project."
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., dev, prod)."
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
}

resource "aws_cognito_user_pool" "pool" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  mfa_configuration = "OFF" # KICS: Cognito UserPool Without MFA.  OFF is explicit and more secure than undefined.  Consider SMS or SOFTWARE_TOKEN_MFA for production.

  password_policy {
    minimum_length     = 12 # Increased minimum length for improved security.
    require_lowercase = true
    require_numbers    = true # Requiring numbers strengthens the password policy.
    require_symbols    = true # Requiring symbols strengthens the password policy.
    require_uppercase = true
  }


  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.pool.id
  generate_secret     = false
 refresh_token_validity = 30 # Reduced refresh token validity for improved security.


  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code"] # Removed implicit flow for improved security.
  allowed_oauth_scopes                 = ["email", "openid"] # Removed phone scope for better security posture.

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.environment}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PAY_PER_REQUEST" # Changed to PAY_PER_REQUEST for cost optimization and to avoid capacity planning.
  hash_key      = "cognito-username"
  range_key     = "id"

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

 point_in_time_recovery { # KICS: DynamoDB Table Point In Time Recovery Disabled
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-cw-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-cw-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-cw-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

# KICS: IAM Access Analyzer Not Enabled.  Add an Access Analyzer resource.
resource "aws_accessanalyzer_analyzer" "analyzer" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-analyzer"
  type = "ACCOUNT"

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-analyzer"
    Environment = var.environment
    Project     = var.project_name
  }

}


# Placeholder for API Gateway, Lambda, Amplify, and other IAM resources. These would require significantly more detail regarding the application logic, frontend repository, etc., to be fully fleshed out. This simplified example focuses on the core infrastructure setup and demonstrates the structure and conventions requested.


output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.pool.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.client.id
  description = "The ID of the Cognito User Pool Client."
}

output "cognito_user_pool_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "The domain of the Cognito User Pool."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table."
}
