terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack."
  default     = "my-stack"
}

variable "environment" {
  description = "The environment to deploy to."
  default     = "production"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API for serverless web application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = var.environment
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
  xray_tracing_enabled = true
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "crud_lambda" {
  function_name = "${var.stack_name}-crud-function"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role = aws_iam_role.lambda_execution_role.arn
  handler = "index.handler"
  code {
    # Assuming the lambda code is zipping and uploading separately.
    s3_bucket = "my-lambda-bucket"
    s3_key    = "path/to/lambda/code.zip"
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-crud-function"
    Environment = var.environment
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.stack_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-execution-role"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.stack_name}-lambda-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:*"]
        Resource = [aws_dynamodb_table.todo_table.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.crud_lambda.function_name}"
  retention_in_days = 14
}

resource "aws_amplify_app" "frontend_app" {
  name  = "amplify-app-${var.stack_name}"
  repository = "https://github.com/myrepo/frontend"
  branch_name = "master"

  build_spec = <<CODE
version: 1
applications:
  - frontend:
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
CODE

  auto_branch_creation {
    pattern       = "master"
    enable_auto_build = true
  }

  oauth_token = "YOUR_GITHUB_ACCESS_TOKEN"

  environment_variables = {
    ENVIRONMENT = var.environment
  }

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.environment
  }
}

output "api_url" {
  value = aws_api_gateway_deployment.api.invoke_url
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}
