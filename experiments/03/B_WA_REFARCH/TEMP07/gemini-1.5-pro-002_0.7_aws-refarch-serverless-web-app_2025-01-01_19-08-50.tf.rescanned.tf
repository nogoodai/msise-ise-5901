terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The application name"
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The GitHub repository URL."
}

variable "github_branch" {
  type        = string
  description = "The GitHub branch name."
  default     = "master"
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token with appropriate permissions."
  sensitive   = true
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  mfa_configuration = "OFF" # Consider using SMS or SOFTWARE_TOKEN for production

 auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "production"
    Project     = var.application_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = true # Best practice is to generate a secret
 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["code"] # Restrict OAuth flows for enhanced security
  allowed_oauth_scopes               = ["email", "phone", "openid"]

  # Use variable for callback and logout URLs
  callback_urls                     = var.callback_urls
  logout_urls                       = var.logout_urls

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = var.application_name
  }
}

variable "callback_urls" {
  type        = list(string)
  description = "List of callback URLs for the Cognito User Pool Client."
  default     = []
}

variable "logout_urls" {
  type        = list(string)
  description = "List of logout URLs for the Cognito User Pool Client."
  default     = []
}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PAY_PER_REQUEST" # Use PAY_PER_REQUEST for better cost optimization in most cases
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
    Project     = var.application_name
  }
}


# IAM Role for API Gateway logging
resource "aws_iam_role" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Sid    = "",
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "api-gateway-cloudwatch-logs-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

# IAM Policy for API Gateway logging
resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs.id
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
"logs:GetLogEvents",
        "logs:FilterLogEvents"


      ],
      # Restrict resource to specific log group
      Resource = aws_cloudwatch_log_group.api_gateway.arn
    }]
  })
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/api-gateway/${var.application_name}"
  retention_in_days = 30 # Adjust as needed
}



# Lambda Functions (Placeholder - needs actual code deployment)
# Example for Add Item function:
resource "aws_lambda_function" "add_item" {
 # ... (Lambda function configuration, including code deployment) ...

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "add-item-lambda-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

# ... (Similar resources for other Lambda functions) ...


# Amplify App
resource "aws_amplify_app" "main" {
  name       = var.application_name
 repository = var.github_repo
  access_token = var.github_access_token
  build_spec = <<-EOT
version: 0.1
frontend:
  phases:
    preBuild:
      npm ci
    build:
      npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOT
  tags = {
    Name        = var.application_name
    Environment = "production"
    Project     = var.application_name
  }
}


# Amplify Branch (auto-build enabled)
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

  tags = {
        Name        = "${var.application_name}-master-branch"
    Environment = "production"
    Project     = var.application_name
  }
}

# IAM Role for Amplify
# ... (Amplify IAM role and policy configuration) ...

# IAM Role and Policies for Lambda functions
# ... (Lambda IAM role and policy configuration for DynamoDB and CloudWatch) ...

resource "aws_accessanalyzer_analyzer" "example" {
  analyzer_name = "example"
  type          = "ACCOUNT"
  tags = {
    Name        = "example-access-analyzer"
    Environment = "production"
    Project     = var.application_name
  }
}


# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}


