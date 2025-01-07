terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources into"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack being deployed"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository URL for Amplify"
  type        = string
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  username_attributes       = ["email"]
  auto_verified_attributes  = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "user-pool-client-${var.stack_name}"

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  tags = {
    Name        = "api-stage-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "usage-plan-${var.stack_name}"
  description = "Usage plan for ${var.stack_name}"

  quota_settings {
    limit = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  api_stages {
    api_id     = aws_api_gateway_rest_api.api.id
    stage      = aws_api_gateway_stage.api_stage.stage_name
  }

  tags = {
    Name        = "usage-plan-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  handler       = "add_item.handler"

  filename      = "path/to/add_item.zip"
  
  tracing_config {
    mode = "Active"
  }

  role          = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMO_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "add-item-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role_${var.stack_name}"

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

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_iam_policy" "dynamodb_policy" {
  name        = "dynamoDB_CRUD_policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.todo_table.arn
        ]
      }
    ]
  })

  tags = {
    Name        = "dynamodb_policy-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "attach_dynamodb_policy" {
  policy_arn = aws_iam_policy.dynamodb_policy.arn
  role       = aws_iam_role.lambda_exec_role.name
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.add_item.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "lambda-log-group-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_amplify_app" "app" {
  name = "amplify-app-${var.stack_name}"

  repository = var.github_repository

  build_spec = <<BUILD_SPEC
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*      
BUILD_SPEC

  oauth_token = var.github_token

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id       = aws_amplify_app.app.id
  branch_name  = "master"

  tags = {
    Name        = "amplify-branch-master-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.add_item.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}
