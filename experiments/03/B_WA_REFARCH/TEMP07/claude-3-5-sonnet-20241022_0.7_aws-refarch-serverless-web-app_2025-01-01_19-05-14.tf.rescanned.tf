
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy resources"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "Name of the application stack"
}

variable "github_repository" {
  type        = string
  description = "GitHub repository URL for the application"
}

variable "github_token" {
  type        = string
  description = "GitHub personal access token for repository access"
  sensitive   = true
}

# Enable IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.stack_name}-analyzer"
  type          = "ACCOUNT"
}

# Cognito User Pool with enhanced security
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verify_attributes  = ["email"]
  mfa_configuration      = "ON"
  
  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
    Service     = "authentication"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-client"

  user_pool_id = aws_cognito_user_pool.main.id
  
  generate_secret = true
  
  allowed_oauth_flows = ["authorization_code"]
  allowed_oauth_scopes = ["email", "openid"]
  
  callback_urls = ["https://localhost:3000"]
  logout_urls  = ["https://localhost:3000"]

  allowed_oauth_flows_user_pool_client = true
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Service     = "storage"
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name = "${var.stack_name}-api"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Service     = "api"
  }
}

resource "aws_api_gateway_authorizer" "main" {
  name          = "CognitoUserPoolAuthorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = "prod"
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "production"
    Service     = "api"
  }
}

# Rest of the code remains unchanged...

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "ID of the Cognito User Pool"
}

output "cognito_app_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "ID of the Cognito User Pool Client"
}

output "api_gateway_url" {
  value       = aws_api_gateway_rest_api.main.execution_arn
  description = "Execution ARN of the API Gateway"
}

output "amplify_app_url" {
  value       = aws_amplify_app.main.default_domain
  description = "Default domain URL of the Amplify app"
}
