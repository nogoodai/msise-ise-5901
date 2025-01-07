# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
  required_version = ">= 1.2.0"
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/todo-app-frontend"
  description = "The GitHub repository URL for the frontend code"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch to use for the frontend code"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "todo_app" {
  name                     = "${var.stack_name}-user-pool"
  email_verification_subject = "Your verification code"
  email_verification_message = "Please verify your email address: {##}"
  alias_attributes           = ["email"]
  auto_verified_attributes   = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain       = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.todo_app.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "todo_table" {
  name           = "${var.stack_name}-todo-table"
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
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-todo-api"
  description = "The API for the todo app"
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "todo"
}

resource "aws_api_gateway_method" "todo_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name           = "${var.stack_name}-todo-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app.arn]
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_method.todo_get, aws_api_gateway_method.todo_post, aws_api_gateway_method.todo_put, aws_api_gateway_method.todo_delete]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name         = "${var.stack_name}-todo-usage-plan"
  description  = "The usage plan for the todo API"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
  }
  quota {
    limit  = 5000
    offset = 100
    period  = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "todo_add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-todo-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "todo_get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-todo-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "todo_get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-todo-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "todo_update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-todo-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "todo_complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-todo-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "todo_delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-todo-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

# API Gateway integration with Lambda functions
resource "aws_api_gateway_integration" "todo_add_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_add_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_get_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_get_all_items_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_get_all_items.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_update_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_update_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_complete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_complete_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_delete_item.function_name}/invocations"
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-todo-app"
  description = "The todo app"
}

resource "aws_amplify_branch" "todo_app_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_backend_environment" "todo_app_env" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "prod"
}

# IAM roles and policies for API Gateway, Amplify, and Lambda
resource "aws_iam_role" "todo_api_gateway_exec" {
  name        = "${var.stack_name}-todo-api-gateway-exec"
  description = "The execution role for the todo API Gateway"

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

resource "aws_iam_policy" "todo_api_gateway_policy" {
  name        = "${var.stack_name}-todo-api-gateway-policy"
  description = "The policy for the todo API Gateway"

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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_api_gateway_attach" {
  role       = aws_iam_role.todo_api_gateway_exec.name
  policy_arn = aws_iam_policy.todo_api_gateway_policy.arn
}

resource "aws_iam_role" "todo_amplify_exec" {
  name        = "${var.stack_name}-todo-amplify-exec"
  description = "The execution role for the todo Amplify"

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

resource "aws_iam_policy" "todo_amplify_policy" {
  name        = "${var.stack_name}-todo-amplify-policy"
  description = "The policy for the todo Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateBackendEnvironment",
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_amplify_attach" {
  role       = aws_iam_role.todo_amplify_exec.name
  policy_arn = aws_iam_policy.todo_amplify_policy.arn
}

resource "aws_iam_role" "todo_lambda_exec" {
  name        = "${var.stack_name}-todo-lambda-exec"
  description = "The execution role for the todo Lambda"

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

resource "aws_iam_policy" "todo_lambda_policy" {
  name        = "${var.stack_name}-todo-lambda-policy"
  description = "The policy for the todo Lambda"

  policy = jsonencode({
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

resource "aws_iam_role_policy_attachment" "todo_lambda_attach" {
  role       = aws_iam_role.todo_lambda_exec.name
  policy_arn = aws_iam_policy.todo_lambda_policy.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.todo_deployment.stage_name
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.todo_add_item.function_name,
    aws_lambda_function.todo_get_item.function_name,
    aws_lambda_function.todo_get_all_items.function_name,
    aws_lambda_function.todo_update_item.function_name,
    aws_lambda_function.todo_complete_item.function_name,
    aws_lambda_function.todo_delete_item.function_name,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.todo_app_branch.branch_name
}
