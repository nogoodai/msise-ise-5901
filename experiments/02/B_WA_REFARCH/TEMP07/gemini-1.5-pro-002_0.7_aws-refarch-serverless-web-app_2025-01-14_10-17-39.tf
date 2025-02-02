terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repository" {
  type = string
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
  }

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  generate_secret                    = false
  callback_urls                      = ["http://localhost:3000"] # Placeholder - Update as needed
  logout_urls                        = ["http://localhost:3000"] # Placeholder - Update as needed

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id

 tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



# DynamoDB Table
resource "aws_dynamodb_table" "main" {
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



# IAM Role for API Gateway Logging to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
 Service = "apigateway.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })

  tags = {
    Name        = "api-gateway-cloudwatch-logs-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# IAM Policy for API Gateway Logging to CloudWatch
resource "aws_iam_policy" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
    ]
  })

  tags = {
    Name        = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}


# Attach IAM Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs" {
  role       = aws_iam_role.api_gateway_cloudwatch_logs.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_logs.arn
}


# (Placeholders for API Gateway, Lambda, and Amplify resources - These require more specific configuration based on your application logic and build process)

# Output the Cognito User Pool ID
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

# Output the Cognito User Pool Client ID
output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

# Output the DynamoDB table name
output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}


