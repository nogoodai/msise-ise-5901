
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
  description = "AWS region where resources will be deployed"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "Name of the application stack"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Deployment environment (e.g. prod, dev, staging)"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository URL for the application"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token for repository access"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verify_attributes  = ["email"]
  mfa_configuration      = "ON"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_symbols   = true
    require_numbers   = true
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = true
  
  allowed_oauth_flows  = ["authorization_code"]
  allowed_oauth_scopes = ["email", "openid"]
  
  callback_urls = ["https://${aws_amplify_app.frontend.default_domain}"]
  logout_urls   = ["https://${aws_amplify_app.frontend.default_domain}"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB Table
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
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.stack_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-api-logs"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name = "${var.stack_name}-api"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# API Gateway Client Certificate
resource "aws_api_gateway_client_certificate" "client_cert" {
  description = "Client certificate for ${var.stack_name} API"
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = "prod"

  client_certificate_id = aws_api_gateway_client_certificate.client_cert.id
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
    Name        = "${var.stack_name}-stage"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.stack_name}-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name        = "${var.stack_name}-analyzer"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Rest of the code remains unchanged...
# Outputs updated with descriptions
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "ID of the Cognito User Pool"
}

output "cognito_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "ID of the Cognito User Pool Client"
}

output "api_gateway_url" {
  value       = aws_api_gateway_stage.prod.invoke_url
  description = "URL of the deployed API Gateway endpoint"
}

output "amplify_app_url" {
  value       = "https://${aws_amplify_app.frontend.default_domain}"
  description = "URL of the deployed Amplify application"
}
