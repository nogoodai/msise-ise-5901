
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
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "app_name" {
  type        = string
  description = "Name of the application"
  default     = "todo-app"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "prod"
}

variable "github_repository" {
  type        = string
  description = "GitHub repository URL"
}

variable "github_token" {
  type        = string
  description = "GitHub personal access token"
  sensitive   = true
}

# Create CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.app_name}-${var.environment}"
  retention_in_days = 7
  
  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.app_name}-user-pool"

  username_attributes      = ["email"]
  auto_verify_attributes  = ["email"]
  mfa_configuration      = "ON"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.app_name}-client"

  user_pool_id = aws_cognito_user_pool.main.id
  
  generate_secret = true
  
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  
  callback_urls = ["https://localhost:3000"]
  logout_urls  = ["https://localhost:3000"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.app_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.environment}"
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
    Environment = var.environment
    Project     = var.app_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name = "${var.app_name}-api"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# Create WAF ACL
resource "aws_wafv2_web_acl" "api_waf" {
  name        = "${var.app_name}-waf"
  description = "WAF for API Gateway"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = "${var.app_name}-waf-metrics"
    sampled_requests_enabled  = true
  }
}

# Associate WAF with API Gateway Stage
resource "aws_wafv2_web_acl_association" "api_waf" {
  resource_arn = aws_api_gateway_stage.prod.arn
  web_acl_arn  = aws_wafv2_web_acl.api_waf.arn
}

# API Gateway Client Certificate
resource "aws_api_gateway_client_certificate" "client_cert" {
  description = "Client certificate for API Gateway"
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  xray_tracing_enabled = true
  client_certificate_id = aws_api_gateway_client_certificate.client_cert.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format         = jsonencode({
      requestId     = "$context.requestId"
      ip           = "$context.identity.sourceIp"
      caller       = "$context.identity.caller"
      user         = "$context.identity.user"
      requestTime  = "$context.requestTime"
      httpMethod   = "$context.httpMethod"
      resourcePath = "$context.resourcePath"
      status       = "$context.status"
      protocol     = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# Enable IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.app_name}-analyzer"
  type         = "ACCOUNT"

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# Rest of the configuration remains the same...

# Updated outputs with descriptions
output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.id
}

output "amplify_app_url" {
  description = "URL of the Amplify application"
  value       = "https://${aws_amplify_branch.master.branch_name}.${aws_amplify_app.main.default_domain}"
}
