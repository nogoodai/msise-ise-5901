# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables for configuration
variable "stack_name" {
  type        = string
  default     = "serverless-web-application"
  description = "Name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/repo"
  description = "GitHub repository URL"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "GitHub branch name"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.stack_name}-user-pool"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  alias_attributes = ["email"]
  tags = {
    Name        = "${var.stack_name}-cognito-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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
  tags = {
    Name        = "${var.stack_name}-todo-table"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-todo-api"
  description = "API for todo application"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  tags = {
    Name        = "${var.stack_name}-todo-api"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "todo"
}

resource "aws_api_gateway_method" "get_todo_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "post_todo_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_method.get_todo_method, aws_api_gateway_method.post_todo_method]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
}

resource "aws_api_gateway_stage" "prod_stage" {
  stage_name    = "prod"
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  deployment_id = aws_api_gateway_deployment.todo_deployment.id
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "get_todo_lambda" {
  filename      = "lambda/get-todo-lambda.zip"
  function_name = "${var.stack_name}-get-todo-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  timeout       = 60
}

resource "aws_lambda_function" "post_todo_lambda" {
  filename      = "lambda/post-todo-lambda.zip"
  function_name = "${var.stack_name}-post-todo-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  timeout       = 60
}

resource "aws_lambda_permission" "get_todo_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_todo_lambda.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "post_todo_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_todo_lambda.function_name
  principal     = "apigateway.amazonaws.com"
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-todo-app"
  description = "Amplify app for todo application"
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment_variable" "github_token" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = aws_amplify_branch.master_branch.branch_name
  environment_variable {
    name  = "GITHUB_TOKEN"
    value = var.github_token
  }
}

# IAM roles and policies for API Gateway, Amplify, and Lambda
resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "Role for API Gateway"
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

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "Policy for API Gateway"
  policy      = jsonencode({
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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.stack_name}-amplify-role"
  description = "Role for Amplify"
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

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Policy for Amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.stack_name}-lambda-exec-role"
  description = "Role for Lambda execution"
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

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for Lambda execution"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "todo_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_stage.prod_stage.stage_name
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.master_branch.branch_name
}
