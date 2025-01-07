terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 0.13"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources into"
  default     = "us-east-1"
}

variable "project_name" {
  description = "The name of the project"
  default     = "serverless-web-app"
}

variable "stack_name" {
  description = "The name of the deployment stack"
  default     = "prod"
}

variable "github_repository" {
  description = "The GitHub repository for the Amplify app"
}

resource "aws_cognito_user_pool" "auth" {
  name = "${var.project_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "${var.project_name}-app-client"
  user_pool_id = aws_cognito_user_pool.auth.id
  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
}

resource "aws_cognito_user_pool_domain" "auth_domain" {
  domain      = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.auth.id
}

resource "aws_dynamodb_table" "todo" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-api"
  description = "API Gateway for the serverless web application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  logging_level              = "INFO"
  data_trace_enabled         = true
}

resource "aws_api_gateway_stage" "stage" {
  stage_name    = var.stack_name
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  xray_tracing_enabled = true
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-stage"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.project_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.stage.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "todo_handler" {
  function_name = "${var.project_name}-handler"
  runtime       = "nodejs12.x"
  handler       = "handler.main"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo.name
    }
  }

  code {
    s3_bucket = var.lambda_code_bucket
    s3_key    = var.lambda_code_key
  }
}

resource "aws_lambda_permission" "api_gateway_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_handler.arn
  principal     = "apigateway.amazonaws.com"
}

resource "aws_amplify_app" "frontend" {
  name  = "${var.project_name}-frontend"
  source_code_repository {
    owner      = "string"
    repository = var.github_repository
  }

  branch {
    branch_name = "master"
    basic_auth_credentials {
      username = "username"
      password = "password"
    }

    build_spec = "{\"version\": 0.1, \"frontend\": {\"phases\": {\"build\": {\"commands\": [\"npm install\", \"npm run build\"]}}, \"artefacts\": {\"baseDirectory\": \"/build\", \"files\": [\"**/*\"]}}}"
    enable_auto_build = true
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

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
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.project_name}-dynamodb-policy"
  description = "Policy for Lambda access to DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo.arn
      },
      {
        Effect = "Allow"
        Action = "logs:CreateLogStream"
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${aws_lambda_function.todo_handler.function_name}:log-stream:*"
      },
      {
        Effect = "Allow"
        Action = "logs:PutLogEvents"
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${aws_lambda_function.todo_handler.function_name}:log-stream:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.auth.id
}

output "api_gateway_invoke_url" {
  description = "API Gateway Invoke URL"
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "dynamodb_table_name" {
  description = "DynamoDB Table Name"
  value       = aws_dynamodb_table.todo.name
}
