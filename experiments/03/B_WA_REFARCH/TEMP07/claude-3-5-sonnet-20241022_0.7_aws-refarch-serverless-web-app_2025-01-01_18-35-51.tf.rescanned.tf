
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
  description = "AWS region where resources will be deployed"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "Name of the application stack"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository URL for the application"
}

variable "github_token" {
  type        = string
  description = "GitHub personal access token for repository access"
  sensitive   = true
}

# IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.stack_name}-analyzer"
  type          = "ACCOUNT"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verify_attributes  = ["email"]
  mfa_configuration      = "ON"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length       = 12
    require_uppercase    = true
    require_lowercase    = true
    require_numbers      = true
    require_symbols      = true
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-client"

  user_pool_id    = aws_cognito_user_pool.main.id
  generate_secret = true
  
  allowed_oauth_flows  = ["authorization_code"]
  allowed_oauth_scopes = ["email", "openid"]
  
  callback_urls = ["https://localhost:3000"]
  logout_urls   = ["https://localhost:3000"]
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  
  hash_key  = "cognito-username"
  range_key = "id"

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
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name = "${var.stack_name}-api"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 1024

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Rest of the code remains the same, but adding tags to previously untagged resources:

resource "aws_iam_role" "lambda_role" {
  # ... existing configuration ...
  tags = {
    Name        = "${var.stack_name}-lambda-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  # ... existing configuration ...
  tags = {
    Name        = "${var.stack_name}-api-gateway-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  # ... existing configuration ...
  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Update outputs with descriptions
output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.id
}

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = "${aws_api_gateway_rest_api.main.execution_arn}/prod"
}

output "amplify_app_url" {
  description = "URL of the Amplify application"
  value       = aws_amplify_app.main.default_domain
}
