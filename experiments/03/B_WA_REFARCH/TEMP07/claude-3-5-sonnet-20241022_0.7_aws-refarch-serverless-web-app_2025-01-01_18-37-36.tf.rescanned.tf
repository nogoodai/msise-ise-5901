
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
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack/environment"
  type        = string
  default     = "prod"
}

variable "github_repository" {
  description = "GitHub repository URL for Amplify"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verify_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"
  
  software_token_mfa_configuration {
    enabled = true
  }

  tags = {
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "todo-app-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "todo-app-client"

  user_pool_id = aws_cognito_user_pool.main.id
  
  generate_secret = true
  
  allowed_oauth_flows = ["authorization_code"]
  allowed_oauth_scopes = ["email", "openid"]
  
  callback_urls = ["https://localhost:3000"]
  logout_urls  = ["https://localhost:3000"]
}

# DynamoDB Table
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
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name = "todo-api-${var.stack_name}"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito-authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${aws_api_gateway_rest_api.todo_api.name}"
  retention_in_days = 30

  tags = {
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

# API Gateway Client Certificate
resource "aws_api_gateway_client_certificate" "client_cert" {
  description = "Client certificate for API Gateway"
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = "prod"

  xray_tracing_enabled = true
  client_certificate_id = aws_api_gateway_client_certificate.client_cert.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId = "$context.requestId"
      ip = "$context.identity.sourceIp"
      caller = "$context.identity.caller"
      user = "$context.identity.user"
      requestTime = "$context.requestTime"
      httpMethod = "$context.httpMethod"
      resourcePath = "$context.resourcePath"
      status = "$context.status"
      protocol = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

# Rest of the code remains unchanged...

# Outputs with descriptions
output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  description = "ID of the Cognito User Pool Client"
  value = aws_cognito_user_pool_client.main.id
}

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value = "${aws_api_gateway_stage.prod.invoke_url}"
}

output "amplify_app_url" {
  description = "URL of the Amplify application"
  value = "https://${aws_amplify_branch.master.branch_name}.${aws_amplify_app.todo_app.default_domain}"
}
