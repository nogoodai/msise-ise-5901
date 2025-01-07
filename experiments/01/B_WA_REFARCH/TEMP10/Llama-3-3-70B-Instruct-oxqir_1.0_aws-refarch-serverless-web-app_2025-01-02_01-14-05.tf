terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
  required_version = ">= 1.4.0"
}

# Variables
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for resources"
}

variable "stack_name" {
  type        = string
  default     = "serverless-web-application"
  description = "Name of the stack"
}

variable "cognito_user_pool_name" {
  type        = string
  default     = "serverless-web-application-user-pool"
  description = "Name of the Cognito User Pool"
}

variable "cognito_user_pool_client_name" {
  type        = string
  default     = "serverless-web-application-user-pool-client"
  description = "Name of the Cognito User Pool Client"
}

variable "cognito_domain_name" {
  type        = string
  default     = "serverless-web-application.auth"
  description = "Domain name for Cognito User Pool"
}

variable "dynamodb_table_name" {
  type        = string
  default     = "todo-table-${var.stack_name}"
  description = "Name of the DynamoDB table"
}

variable "api_gateway_name" {
  type        = string
  default     = "serverless-web-application-api-gateway"
  description = "Name of the API Gateway"
}

variable "lambda_function_name" {
  type        = string
  default     = "serverless-web-application-lambda-function"
  description = "Name of the Lambda function"
}

variable "amplify_app_name" {
  type        = string
  default     = "serverless-web-application-amplify-app"
  description = "Name of the Amplify app"
}

variable "github_repository" {
  type        = string
  default     = "https://github.com/user/repository"
  description = "GitHub repository URL for Amplify app"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "GitHub branch for Amplify app"
}

# AWS Provider
provider "aws" {
  region = var.aws_region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                     = var.cognito_user_pool_name
  username_attributes      = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_configuration {
    source_arn = aws_ses_configuration_set.example.arn
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = var.cognito_user_pool_client_name
  user_pool_id        = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["implicit", "authorization_code"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = var.cognito_domain_name
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB table
resource "aws_dynamodb_table" "dynamodb_table" {
  name         = var.dynamodb_table_name
  billing_mode = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  global_secondary_index {
    name               = "id-index"
    hash_key           = "id"
    projection_type    = "INCLUDE"
    non_key_attributes = ["id"]
  }
  table_class = "STANDARD"
  server_side_encryption {
    enabled = true
  }
  point_in_time_recovery {
    enabled = true
  }
}

# API Gateway
resource "aws_api_gateway" "api_gateway" {
  name        = var.api_gateway_name
  description = "API Gateway for serverless web application"
}

resource "aws_api_gateway_rest_api" "rest_api" {
  name        = var.api_gateway_name
  description = "API Gateway REST API for serverless web application"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name           = "Cognito Authorizer"
  rest_api_id    = aws_api_gateway_rest_api.rest_api.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  parent_id   = aws_api_gateway_rest_api.rest_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.lambda_function_name}/invocations"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.get_integration]
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "Serverless Web Application Usage Plan"
  description = "Usage plan for serverless web application"

  api_stages {
    api_id = aws_api_gateway_rest_api.rest_api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }

  quota {
    limit  = 5000
    offset = 0
    period = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda function
resource "aws_lambda_function" "lambda_function" {
  filename      = "lambda_function.zip"
  function_name = var.lambda_function_name
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_role.arn
}

resource "aws_iam_role" "lambda_role" {
  name        = "Lambda Execution Role"
  description = "Role for Lambda function execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "Lambda Policy"
  description = "Policy for Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.lambda_function_name}"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.dynamodb_table.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Amplify app
resource "aws_amplify_app" "amplify_app" {
  name        = var.amplify_app_name
  description = "Amplify app for serverless web application"
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "amplify_environment" {
  app_id      = aws_amplify_app.amplify_app.id
  environment = "prod"
}

resource "aws_amplify_app_version" "amplify_app_version" {
  app_id            = aws_amplify_app.amplify_app.id
  source {
    url = var.github_repository
    build_spec = templatefile("buildspec.yml", {})
    version     = "HEAD"
  }
}

# IAM roles and policies
resource "aws_iam_role" "api_gateway_role" {
  name        = "API Gateway Execution Role"
  description = "Role for API Gateway execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "API Gateway Policy"
  description = "Policy for API Gateway"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/${var.api_gateway_name}"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "Amplify Execution Role"
  description = "Role for Amplify execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "Amplify Policy"
  description = "Policy for Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetEnvironment",
        ]
        Effect = "Allow"
        Resource = "arn:aws:amplify:${var.aws_region}:${data.aws_caller_identity.current.account_id}:apps/${var.amplify_app_name}"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Data sources
data "aws_caller_identity" "current" {
}

data "aws_region" "current" {
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.rest_api.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.lambda_function.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_id" {
  value = aws_amplify_branch.amplify_branch.id
}
