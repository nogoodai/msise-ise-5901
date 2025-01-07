# Terraform configuration for AWS serverless web application

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

# Variables
variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "Stack name for resource naming"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository URL for Amplify frontend hosting"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.stack_name}-user-pool"
  email_configuration = {
    email_sending_account = "COGNITO_DEFAULT"
  }
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  username_attributes        = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  auto_verified_attributes = ["email"]
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
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
  server_side_encryption {
    enabled = true
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.stack_name}-api-gateway"
  description = "API Gateway for serverless web application"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "put_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "delete_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_method.get_item_method,
    aws_api_gateway_method.post_item_method,
    aws_api_gateway_method.put_item_method,
    aws_api_gateway_method.delete_item_method
  ]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for API Gateway"
}

resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
  key_type      = "API_KEY"
  key           = "my-api-key"
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "add_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "get_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "put_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-put-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "delete_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "amplify_app" {
  name        = "${var.stack_name}-amplify-app"
  description = "Amplify app for frontend hosting"
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

# IAM roles and policies
resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.stack_name}-lambda-exec-role"
  description = "IAM role for Lambda execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  name   = "${var.stack_name}-lambda-exec-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role" "api_gateway_exec_role" {
  name        = "${var.stack_name}-api-gateway-exec-role"
  description = "IAM role for API Gateway execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_exec_policy" {
  name   = "${var.stack_name}-api-gateway-exec-policy"
  role   = aws_iam_role.api_gateway_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role" "amplify_exec_role" {
  name        = "${var.stack_name}-amplify-exec-role"
  description = "IAM role for Amplify execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy" "amplify_exec_policy" {
  name   = "${var.stack_name}-amplify-exec-policy"
  role   = aws_iam_role.amplify_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:CreateBranch",
          "amplify:UpdateBranch",
          "amplify:DeleteBranch",
        ]
        Resource = aws_amplify_app.amplify_app.id
        Effect    = "Allow"
      },
    ]
  })
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "lambda_add_item_function_arn" {
  value = aws_lambda_function.add_item_lambda.arn
}

output "lambda_get_item_function_arn" {
  value = aws_lambda_function.get_item_lambda.arn
}

output "lambda_put_item_function_arn" {
  value = aws_lambda_function.put_item_lambda.arn
}

output "lambda_delete_item_function_arn" {
  value = aws_lambda_function.delete_item_lambda.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
