# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

# Configure AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "stack_name" {
  type        = string
  default     = "serverless-web-app"
  description = "The name of the application stack"
}

variable "github_repository" {
  type        = string
  sensitive   = true
  description = "The GitHub repository URL for the frontend application"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "The GitHub personal access token for Amplify"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  email_verification_message  = "Your verification code is {####}."
  email_configuration {
    email_sending_account = "DEVELOPER"
  }

  policies {
    password_policy {
      minimum_length    = 6
      require_uppercase = true
      require_lowercase = true
    }
  }

  alias_attributes = ["email"]
  auto_verified_attributes = ["email"]
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name = "${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret     = false
  allowed_oauth_flows = ["client_credentials", "authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "${var.stack_name}-todo-table"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
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
    Name        = "${var.stack_name}-todo-table"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "The execution role for the API Gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "The policy for the API Gateway execution role"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "lambda_role" {
  name        = "${var.stack_name}-lambda-role"
  description = "The execution role for the Lambda function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "The policy for the Lambda execution role"

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
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.stack_name}-amplify-role"
  description = "The execution role for the Amplify service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "The policy for the Amplify execution role"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:UpdateApp",
          "amplify:DeleteApp",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = var.stack_name
  description = "The Amplify app for the frontend application"

  build_spec = file("${path.module}/buildspec.yml")
  environment_variables = {
    GITHUB_REPO = var.github_repository
    GITHUB_TOKEN = var.github_token
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

# Lambda Functions
resource "aws_lambda_function" "add_item_function" {
  filename      = "${path.module}/add-item-lambda.zip"
  function_name = "${var.stack_name}-add-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "${path.module}/get-item-lambda.zip"
  function_name = "${var.stack_name}-get-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "get_all_items_function" {
  filename      = "${path.module}/get-all-items-lambda.zip"
  function_name = "${var.stack_name}-get-all-items-lambda"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "update_item_function" {
  filename      = "${path.module}/update-item-lambda.zip"
  function_name = "${var.stack_name}-update-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "complete_item_function" {
  filename      = "${path.module}/complete-item-lambda.zip"
  function_name = "${var.stack_name}-complete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "delete_item_function" {
  filename      = "${path.module}/delete-item-lambda.zip"
  function_name = "${var.stack_name}-delete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = var.stack_name
  description = "The API Gateway for the serverless application"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name        = "cognito-authorizer"
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.post_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item_function.arn}/invocations"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [aws_api_gateway_integration.post_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name        = var.stack_name
  description = "The usage plan for the API Gateway"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
  }

  quota {
    limit  = 5000
    offset = 1
    period = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.api_deployment.stage_name
}

output "lambda_add_item_function_arn" {
  value = aws_lambda_function.add_item_function.arn
}

output "lambda_get_item_function_arn" {
  value = aws_lambda_function.get_item_function.arn
}

output "lambda_get_all_items_function_arn" {
  value = aws_lambda_function.get_all_items_function.arn
}

output "lambda_update_item_function_arn" {
  value = aws_lambda_function.update_item_function.arn
}

output "lambda_complete_item_function_arn" {
  value = aws_lambda_function.complete_item_function.arn
}

output "lambda_delete_item_function_arn" {
  value = aws_lambda_function.delete_item_function.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.master_branch.branch_name
}
