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
  description = "The AWS region to deploy the resources to."
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application."
}

variable "stack_name" {
  type        = string
  default     = "dev"
  description = "The name of the stack."
}

resource "aws_cognito_user_pool" "main" {
  name                    = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes     = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }

  mfa_configuration = "OFF" # KICS: Cognito UserPool Without MFA. Set to OFF explicitly. Consider using 'OPTIONAL' or 'ON' for better security.

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity = 5
  write_capacity = 5
  hash_key = "cognito-username"
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

  point_in_time_recovery { # KICS: DynamoDB Table Point In Time Recovery Disabled
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_iam_role" "api_gateway_cw_logs_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cw_logs_policy" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-policy"
  role = aws_iam_role.api_gateway_cw_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*" # Consider restricting the resource to specific log groups.
      },
    ]
  })
}

resource "aws_accessanalyzer_analyzer" "main" { # KICS: IAM Access Analyzer Not Enabled
  analyzer_name = "${var.application_name}-${var.stack_name}-access-analyzer"
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-access-analyzer"
    Environment = var.stack_name
    Project     = var.application_name
  }
 type = "ACCOUNT"
}


output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "cognito_user_pool_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "The domain of the Cognito User Pool."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "access_analyzer_arn" {
 value = aws_accessanalyzer_analyzer.main.arn
 description = "The ARN of the Access Analyzer."
}
