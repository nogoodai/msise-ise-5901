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
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "todo-app"
}

variable "stack_name" {
  type = string
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
}


resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.project_name}-${var.environment}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

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
    Environment = var.environment
    Project     = var.project_name
  }
}


# Placeholder for API Gateway, Lambda, Amplify, and IAM resources.
# These would require more detailed specifications (e.g., Lambda function code, Amplify repository URL)
# to generate fully functional Terraform configurations.  The structure below demonstrates
# the expected organization and resource types.

# API Gateway
# resource "aws_api_gateway_rest_api" "main" {}
# resource "aws_api_gateway_resource" "main" {}
# resource "aws_api_gateway_method" "main" {}
# ...

# Lambda
# resource "aws_lambda_function" "add_item" {}
# resource "aws_lambda_function" "get_item" {}
# ...

# Amplify
# resource "aws_amplify_app" "main" {}
# resource "aws_amplify_branch" "main" {}

# IAM
# resource "aws_iam_role" "api_gateway_role" {}
# resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {}
# resource "aws_iam_role" "lambda_role" {}
# resource "aws_iam_role_policy" "lambda_dynamodb_policy" {}
# resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {}
# resource "aws_iam_role" "amplify_role" {}
# ...


# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}


