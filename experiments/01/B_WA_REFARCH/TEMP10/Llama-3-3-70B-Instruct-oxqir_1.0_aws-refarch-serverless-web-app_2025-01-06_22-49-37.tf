# Required terraform block
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region = "us-west-2"
}

# Variables for stack name and application name
variable "stack_name" {
  type        = string
  default     = "serverless-web-app"
}

variable "application_name" {
  type        = string
  default     = "todo-app"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "todo_app" {
  name                     = "${var.application_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  email_configuration {
    email_sending_account = "DEVELOPER"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "todo_app_client" {
  name                = "${var.application_name}-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  supported_identity_providers = [
    "COGNITO"
  ]
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["https://${var.application_name}.com/callback"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_app_domain" {
  domain       = "${var.application_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.todo_app.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "todo_items_table" {
  name           = "todo-table-${var.stack_name}"
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
  key_schema = [
    {
      attribute_name = "cognito-username"
      key_type       = "HASH"
    },
    {
      attribute_name = "id"
      key_type       = "RANGE"
    }
  ]
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# IAM role for API Gateway to log to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name        = "${var.application_name}-api-gateway-cloudwatch-role"
  description = "API Gateway role to log to CloudWatch"

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
  tags = {
    Name        = "${var.application_name}-api-gateway-cloudwatch-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# IAM policy for API Gateway to log to CloudWatch
resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
  name        = "${var.application_name}-api-gateway-cloudwatch-policy"
  description = "API Gateway policy to log to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach IAM policy to API Gateway role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-api"
  description = "API for todo application"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

# API Gateway usage plan
resource "aws_api_gateway_usage_plan" "todo_api_usage_plan" {
  name        = "${var.application_name}-usage-plan"
  description = "Usage plan for todo API"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_api_deployment.stage_name
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

# Cognito User Pool Authorizer for API Gateway
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                             = "${var.application_name}-cognito-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.todo_api.id
  type                             = "COGNITO_USER_POOLS"
  provider_arns                    = [aws_cognito_user_pool.todo_app.arn]
}

# Lambda function for CRUD operations on DynamoDB
resource "aws_lambda_function" "todo_item_lambda" {
  filename         = "index.js"
  function_name    = "${var.application_name}-todo-item-lambda"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.todo_item_lambda_role.arn
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_items_table.name
    }
  }
  tags = {
    Name        = "${var.application_name}-todo-item-lambda"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# IAM role for Lambda function to interact with DynamoDB and publish metrics to CloudWatch
resource "aws_iam_role" "todo_item_lambda_role" {
  name        = "${var.application_name}-todo-item-lambda-role"
  description = "Lambda role to interact with DynamoDB and publish metrics to CloudWatch"

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
  tags = {
    Name        = "${var.application_name}-todo-item-lambda-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# IAM policy for Lambda function to interact with DynamoDB and publish metrics to CloudWatch
resource "aws_iam_policy" "todo_item_lambda_policy" {
  name        = "${var.application_name}-todo-item-lambda-policy"
  description = "Lambda policy to interact with DynamoDB and publish metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_items_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach IAM policy to Lambda role
resource "aws_iam_role_policy_attachment" "todo_item_lambda_attachment" {
  role       = aws_iam_role.todo_item_lambda_role.name
  policy_arn = aws_iam_policy.todo_item_lambda_policy.arn
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "todo_app" {
  name        = var.application_name
  description = "Amplify app for todo application"
  platform    = "WEB"
}

# Amplify branch for master branch
resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"
}

# Amplify GitHub repository
resource "aws_amplify_app" "todo_app_github" {
  name        = var.application_name
  description = "Amplify app for todo application"
  platform    = "WEB"
  github_token = "your-github-token"
  environment_variables = {
    KEY = "VALUE"
  }
}

# IAM role for Amplify to manage resources
resource "aws_iam_role" "amplify_role" {
  name        = "${var.application_name}-amplify-role"
  description = "Amplify role to manage resources"

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
  tags = {
    Name        = "${var.application_name}-amplify-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# IAM policy for Amplify to manage resources
resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.application_name}-amplify-policy"
  description = "Amplify policy to manage resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:CreateBranch",
          "amplify:DeleteBranch",
          "amplify:UpdateBranch"
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.todo_app.arn
      }
    ]
  })
}

# Attach IAM policy to Amplify role
resource "aws_iam_role_policy_attachment" "amplify_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Output key ARNs and IDs
output "cognito_user_pool_arn" {
  value = aws_cognito_user_pool.todo_app.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_items_table.arn
}

output "dynamodb_table_id" {
  value = aws_dynamodb_table.todo_items_table.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.todo_api.id}.execute-api.us-west-2.amazonaws.com/prod"
}

output "lambda_function_arn" {
  value = aws_lambda_function.todo_item_lambda.arn
}

output "lambda_function_id" {
  value = aws_lambda_function.todo_item_lambda.id
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_app_arn" {
  value = aws_amplify_app.todo_app.arn
}
