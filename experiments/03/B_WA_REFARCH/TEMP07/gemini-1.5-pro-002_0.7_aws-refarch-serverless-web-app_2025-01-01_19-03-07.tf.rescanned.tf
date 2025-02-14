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
  description = "The name of the stack. Used for naming resources."
  default     = "serverless-todo-app"
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

variable "domain_prefix" {
  type        = string
  description = "The prefix for the Cognito domain."
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  email_verification_message = "Your verification code is: {####}"
  email_verification_subject = "Verify your email"

  password_policy {
    minimum_length = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }


  mfa_configuration = "OFF" # Consider enabling MFA for enhanced security

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.stack_name}-cognito-user-pool"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]


  # Update with actual callback URLs. Using localhost is insecure for production.
  callback_urls = ["http://localhost:3000/"]



  tags = {
    Name        = "${var.stack_name}-cognito-user-pool-client"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

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

  tags = {
    Name        = "${var.stack_name}-dynamodb-table"
    Environment = "production"
    Project     = var.stack_name
  }
}



# API Gateway, Lambda, Amplify, IAM Roles and Policies are complex and require more detailed information about lambda function code, build process etc. to generate accurate and complete Terraform code.  The following are placeholders that would need to be expanded.


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
 minimum_compression_size = 0

  tags = {
    Name        = "${var.stack_name}-api-gateway"
    Environment = "production"
    Project     = var.stack_name
  }
}

# Placeholder for Lambda functions - needs detailed implementation
# resource "aws_lambda_function" "example" {
#   # ...
# }

# Placeholder for Amplify app - needs detailed implementation, including build settings
# resource "aws_amplify_app" "main" {
#   # ...
# }

# Placeholder for IAM roles and policies - needs fine-grained permissions based on actual resource usage
# resource "aws_iam_role" "api_gateway_role" {
#   # ...
# }




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


