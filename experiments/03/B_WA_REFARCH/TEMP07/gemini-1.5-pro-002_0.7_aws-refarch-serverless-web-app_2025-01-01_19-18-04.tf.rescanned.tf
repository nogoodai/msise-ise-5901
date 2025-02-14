terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a version constraint
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., dev, prod)."
  default     = "dev"
}

variable "project_name" {
  type        = string
  description = "The project name."
  default     = "todo-app"
}

variable "stack_name" {
  type        = string
  description = "The stack name."
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length    = 12 # Increased minimum length
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true # Added number requirement
    require_symbols   = true # Added symbol requirement
  }

  mfa_configuration = "SOFTWARE_TOKEN_MFA" # Enabled MFA


  tags = {
    Environment = var.environment
    Project     = var.project_name
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code"] # Removed implicit flow
  allowed_oauth_scopes                = ["email", "openid"] # Removed phone scope

  generate_secret = false


  prevent_user_existence_errors = "ENABLED" # Addressed potential error condition
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
    Name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"

  }
}


resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.project_name}-${var.environment}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-domain"
  }
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Changed to on-demand billing
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

 point_in_time_recovery { # Enabled point-in-time recovery
    enabled = true
  }
  tags = {
    Environment = var.environment
    Project     = var.project_name
    Name        = "todo-table-${var.stack_name}"

  }
}


resource "aws_accessanalyzer_analyzer" "main" { # Added Access Analyzer
  analyzer_name = "${var.project_name}-${var.environment}-${var.stack_name}-analyzer"
  type          = "ACCOUNT"

  tags = {
    Environment = var.environment
    Project     = var.project_name
        Name        = "${var.project_name}-${var.environment}-${var.stack_name}-analyzer"

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

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}


