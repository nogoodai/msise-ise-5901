
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

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.app_name}-user-pool-${var.environment}"

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
    Environment = var.environment
    Project     = var.app_name
    ManagedBy   = "terraform"
  }
}

# Rest of resources remain the same, adding necessary security improvements

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
    ManagedBy   = "terraform"
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format         = "$context.identity.sourceIp $context.identity.caller $context.identity.user [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
  }

  client_certificate_id = aws_api_gateway_client_certificate.main.id

  tags = {
    Environment = var.environment
    Project     = var.app_name
    ManagedBy   = "terraform"
  }
}

# New resources for API Gateway security
resource "aws_api_gateway_client_certificate" "main" {
  description = "Client certificate for ${var.app_name} API Gateway"
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.app_name}-${var.environment}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
    Project     = var.app_name
    ManagedBy   = "terraform"
  }
}

resource "aws_wafregional_web_acl" "api_gateway" {
  name        = "${var.app_name}-waf-${var.environment}"
  metric_name = replace("${var.app_name}waf${var.environment}", "-", "")

  default_action {
    type = "BLOCK"
  }

  rule {
    action {
      type = "ALLOW"
    }
    priority = 1
    rule_id  = aws_wafregional_rule.api_gateway.id
  }
}

resource "aws_wafregional_rule" "api_gateway" {
  name        = "${var.app_name}-waf-rule-${var.environment}"
  metric_name = replace("${var.app_name}wafrule${var.environment}", "-", "")
}

resource "aws_wafregional_web_acl_association" "api_gateway" {
  resource_arn = aws_api_gateway_stage.prod.arn
  web_acl_id   = aws_wafregional_web_acl.api_gateway.id
}

# IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.app_name}-analyzer"
  type         = "ACCOUNT"

  tags = {
    Environment = var.environment
    Project     = var.app_name
    ManagedBy   = "terraform"
  }
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
    ManagedBy   = "terraform"
  }
}

# Outputs with descriptions
output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.id
}

output "api_gateway_url" {
  description = "URL of the API Gateway deployment"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_url" {
  description = "URL of the Amplify application"
  value       = "https://${aws_amplify_branch.master.branch_name}.${aws_amplify_app.main.default_domain}"
}
