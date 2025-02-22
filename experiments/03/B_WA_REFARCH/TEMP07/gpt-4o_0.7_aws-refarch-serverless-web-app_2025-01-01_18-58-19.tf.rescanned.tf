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
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack."
  type        = string
  default     = "my-stack"
}

variable "github_repo" {
  description = "GitHub repository for Amplify source."
  type        = string
}

variable "github_token" {
  description = "GitHub token for accessing the repository."
  type        = string
  sensitive   = true
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  mfa_configuration = "OPTIONAL"

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "app-client-${var.stack_name}"

  o_auth_flows {
    authorization_code_grant = true
    implicit_flow            = true
  }

  o_auth_scopes = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

  hash_key  = "cognito-username"
  range_key = "id"

  read_capacity  = 5
  write_capacity = 5

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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "api-gateway-${var.stack_name}"
  description = "API Gateway for serverless web application"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.api_gateway.id
  deployment_id        = aws_api_gateway_deployment.api_deployment.id
  description          = "Production stage"
  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log_group.arn
    format          = "$context.identity.sourceIp - $context.identity.caller [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
  }

  tags = {
    Name        = "api-stage-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/api-gateway/${var.stack_name}"

  retention_in_days = 14
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  tags = {
    Name        = "usage-plan-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "crud_lambda" {
  function_name = "crud-lambda-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "crud-lambda-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_app" "frontend" {
  name        = "amplify-app-${var.stack_name}"
  repository  = var.github_repo
  oauth_token = var.github_token

  build_spec = <<EOF
version: 0.1
frontend:
  phases:
    build:
      commands:
        - npm install
        - npm run build
  artifacts:
    baseDirectory: /path/to/build/output
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  branch {
    branch_name = "master"
    framework   = "react"
    stage       = "PRODUCTION"
    auto_build  = true
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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

  inline_policy {
    name   = "LambdaDynamoDBPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem",
            "dynamodb:Scan",
            "dynamodb:Query",
            "dynamodb:GetItem"
          ]
          Effect   = "Allow"
          Resource = aws_dynamodb_table.todo_table.arn
        },
        {
          Action   = "logs:*"
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action   = "xray:PutTraceSegments"
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

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

  inline_policy {
    name   = "APIGatewayCloudWatchLogsPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = "logs:*"
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

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

  inline_policy {
    name   = "AmplifyAdminPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = "amplify:*"
          Effect   = "Allow"
          Resource = "*"
        }
      ]
    })
  }

  tags = {
    Name        = "amplify-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito User Pool"
}

output "api_gateway_url" {
  value       = aws_api_gateway_rest_api.api_gateway.execution_arn
  description = "The execution ARN of the API Gateway"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "amplify_app_id" {
  value       = aws_amplify_app.frontend.id
  description = "The ID of the Amplify App"
}
