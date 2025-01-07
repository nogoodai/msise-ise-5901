terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name."
  default     = "my-stack"
}

variable "amplify_git_branch" {
  description = "The git branch for the Amplify app."
  default     = "master"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

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
    Name        = "user-pool-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain      = "${var.stack_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for the serverless web app."

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id

  # Configure logging and metrics
  xray_tracing_enabled = true

  tags = {
    Name        = "api-stage-prod-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_method.any]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "BasicUsagePlan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit  = 100
    rate_limit   = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "lambda-add-item-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "lambda_execution" {
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
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name = "lambda_policy_${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
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
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_amplify_app" "amplify" {
  name  = "amplify-app-${var.stack_name}"
  repository = "https://github.com/your-username/your-repo-name"

  auto_branch_creation_config {
    enable_auto_build = true

    environment_variables = {
      NODE_ENV = "production"
    }
  }

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "api_gw_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_policy" "api_gw_logging_policy" {
  name = "api_gw_logging_policy_${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apigw_logging" {
  role       = aws_iam_role.api_gw_role.name
  policy_arn = aws_iam_policy.api_gw_logging_policy.arn
}

output "user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "The URL of the API Gateway deployment"
  value       = aws_api_gateway_deployment.deployment.invoke_url
}
