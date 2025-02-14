
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

# Variables
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy resources"
}

variable "app_name" {
  type        = string
  default     = "todo-app"
  description = "Name of the application"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment name (e.g. prod, dev, staging)"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository URL"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token"
}

# IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.app_name}-analyzer"
  type          = "ACCOUNT"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.app_name}-user-pool"

  username_attributes      = ["email"]
  auto_verify_attributes  = ["email"]

  mfa_configuration = "ON"
  
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
    Name        = "${var.app_name}-user-pool"
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.app_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.app_name}-client"

  user_pool_id = aws_cognito_user_pool.main.id
  
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid"]
  
  generate_secret = true
  
  callback_urls = ["https://localhost:3000"]
  logout_urls   = ["https://localhost:3000"]
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.environment}"
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
    Name        = "todo-table-${var.environment}"
    Environment = var.environment
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name = "${var.app_name}-api"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Name        = "${var.app_name}-api"
    Environment = var.environment
  }
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.app_name}-${var.environment}"
  retention_in_days = 30

  tags = {
    Name        = "${var.app_name}-api-logs"
    Environment = var.environment
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = "prod"

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format         = jsonencode({
      requestId    = "$context.requestId"
      ip          = "$context.identity.sourceIp"
      caller      = "$context.identity.caller"
      user        = "$context.identity.user"
      requestTime = "$context.requestTime"
      httpMethod  = "$context.httpMethod"
      resourcePath = "$context.resourcePath"
      status      = "$context.status"
      protocol    = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name        = "${var.app_name}-stage"
    Environment = var.environment
  }
}

# Rest of the code remains unchanged...

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "Cognito User Pool ID"
}

output "cognito_app_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "Cognito App Client ID"
}

output "api_gateway_url" {
  value       = aws_api_gateway_stage.prod.invoke_url
  description = "API Gateway Stage URL"
}

output "amplify_app_url" {
  value       = "https://${aws_amplify_branch.master.branch_name}.${aws_amplify_app.frontend.default_domain}"
  description = "Amplify App URL"
}
