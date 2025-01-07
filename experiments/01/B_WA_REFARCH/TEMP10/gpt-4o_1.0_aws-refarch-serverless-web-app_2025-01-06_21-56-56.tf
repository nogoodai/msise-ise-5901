terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack to use in resource naming."
  type        = string
  default     = "prod"
}

# Cognito User Pool
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
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false

  oauth {
    flows = ["authorization_code", "implicit"]
    scopes = ["email", "phone", "openid"]
  }

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
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

  provisioned_throughput {
    read_capacity  = 5
    write_capacity = 5
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "serverless-api-${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = file("openapi.yaml")  # Assuming openapi.yaml is present in the working directory

  tags = {
    Name        = "serverless-api-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"

  xray_tracing_enabled = true

  tags = {
    Name        = "api-stage-prod-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod.stage_name
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

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name         = "cognito-authorizer"
  rest_api_id  = aws_api_gateway_rest_api.api.id
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  type          = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"
}

# Lambda Functions
resource "aws_lambda_function" "crud_lambda" {
  function_name = "${each.key}-${var.stack_name}"

  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  xray_tracing_config {
    mode = "Active"
  }

  source_code_hash = filebase64sha256("path/to/function/lambda.zip")
  filename         = "path/to/function/lambda.zip"

  tags = {
    Name        = "${each.key}-lambda-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }

  dynamic "environment" {
    for_each = { "Variables" = { DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name } }

    content {
      variables = { local.environment_item = environment.value }
    }
  }

  depends_on = [aws_api_gateway_rest_api.api]
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name = "amplify-${var.stack_name}"

  repository = "https://github.com/your-repo/your-app"

  build_spec = <<EOT
version: 1.0
frontend:
  phases:
    preBuild:
      commands:
        - yarn || npm install
    build:
      commands:
        - yarn run build || npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOT

  tags = {
    Name        = "amplify-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name        = "amplify-branch-master-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Scan"]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "amplify-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
