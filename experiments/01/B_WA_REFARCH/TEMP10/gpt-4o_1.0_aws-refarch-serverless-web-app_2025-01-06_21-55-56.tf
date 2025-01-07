terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for resource identification"
  type        = string
  default     = "prod"
}

variable "github_repository" {
  description = "The GitHub repository URL for Amplify source"
  type        = string
}

resource "aws_cognito_user_pool" "authentication" {
  name = "user_pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "user_pool-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.authentication.id

  # Enable OAuth2 flows
  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  callbacks                 = [var.github_repository]
  generate_secret           = false
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "client-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.authentication.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  hash_key  = "cognito-username"
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for the serverless web app"
  endpoint_configuration {
    types = ["EDGE"]
  }

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_resource" "todo" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item-{id}"
}

resource "aws_lambda_function" "crud_operations" {
  for_each = toset(["add", "get", "get_all", "update", "complete", "delete"])

  function_name = "${each.key}_item_function-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  # Assume appropriate Lambda deployment package is available
  filename = "path/to/lambda_function_${each.key}.zip"

  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "lambda-${each.key}-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_app" "frontend_app" {
  name              = "frontend-${var.stack_name}"
  repository        = var.github_repository
  oauth_token       = var.github_token

  branch {
    branch_name = "master"
    enable_auto_build = true
  }

  tags = {
    Name        = "amplify-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_execution_role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "lambda-execution-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda_dynamodb_policy-${var.stack_name}"
  description = "Policy for Lambda to interact with DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.authentication.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend_app.app_id
}
