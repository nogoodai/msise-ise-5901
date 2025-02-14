
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

variable "github_repo" {
  type        = string
  description = "GitHub repository URL"
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token"
  sensitive   = true
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.app_name}-${var.environment}"
  retention_in_days = 30
  
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
    require_symbols   = true
    require_numbers   = true
  }

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# Rest of the configuration remains the same, but with these key changes:

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
  
  xray_tracing_enabled = true
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format         = jsonencode({
      requestId               = "$context.requestId"
      sourceIp               = "$context.identity.sourceIp"
      requestTime            = "$context.requestTime"
      protocol              = "$context.protocol"
      httpMethod            = "$context.httpMethod"
      resourcePath          = "$context.resourcePath"
      routeKey              = "$context.routeKey"
      status                = "$context.status"
      responseLength        = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }

  client_certificate_id = aws_api_gateway_client_certificate.main.id

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# API Gateway Client Certificate
resource "aws_api_gateway_client_certificate" "main" {
  description = "Client certificate for ${var.app_name} API"
}

# API Gateway Rest API
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

# IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.app_name}-analyzer"
  type         = "ACCOUNT"

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# DynamoDB Table with Point-in-Time Recovery
resource "aws_dynamodb_table" "todo_table" {
  # ... existing configuration ...
  
  point_in_time_recovery {
    enabled = true
  }
}

# WAF Web ACL for API Gateway
resource "aws_wafv2_web_acl" "api" {
  name        = "${var.app_name}-web-acl"
  description = "WAF Web ACL for API Gateway"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled  = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = "${var.app_name}-web-acl-metric"
    sampled_requests_enabled  = true
  }

  tags = {
    Environment = var.environment
    Project     = var.app_name
  }
}

# Associate WAF Web ACL with API Gateway Stage
resource "aws_wafregional_web_acl_association" "api" {
  resource_arn = aws_api_gateway_stage.prod.arn
  web_acl_id   = aws_wafv2_web_acl.api.id
}

