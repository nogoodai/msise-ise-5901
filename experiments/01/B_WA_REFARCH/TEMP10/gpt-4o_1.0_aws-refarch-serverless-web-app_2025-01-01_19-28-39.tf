terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name to use for resource identification"
  default     = "my-stack"
}

variable "project_name" {
  description = "The project name for tagging and identification"
  default     = "serverless-web-app"
}

variable "environment" {
  description = "Environment for resource tagging"
  default     = "production"
}

# Cognito
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                   = "${var.project_name}-${var.stack_name}-user-pool-client"
  user_pool_id           = aws_cognito_user_pool.user_pool.id
  generate_secret        = false
  allowed_oauth_flows    = ["code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "${var.project_name}-${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.project_name}-${var.stack_name}-api"
  description = "API Gateway for the ${var.project_name}"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.api_gateway.id
  
  variables = {
    lambdaAlias = "prod"
  }

  xray_tracing_enabled = true
}

resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name = "${var.project_name}-usage-plan"
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
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                = "cognito_authorizer"
  rest_api_id         = aws_api_gateway_rest_api.api_gateway.id
  type                = "COGNITO_USER_POOLS"
  provider_arns       = [aws_cognito_user_pool.user_pool.arn]
  authorizer_result_ttl_in_seconds = 300
}

# Lambda Functions
locals {
  lambda_memory_size = 1024
  lambda_timeout     = 60
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-${var.stack_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name        = "${var.project_name}-${var.stack_name}-lambda-policy"
  role        = aws_iam_role.lambda_execution_role.id
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "${aws_dynamodb_table.todo_table.arn}"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource   = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = local.lambda_memory_size
  timeout       = local.lambda_timeout
  role          = aws_iam_role.lambda_execution_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

# More Lambda functions: get item, get all items, update, complete, delete...

# Amplify
resource "aws_amplify_app" "amplify_app" {
  name           = "${var.project_name}-${var.stack_name}-amplify-app"
  repository     = "https://github.com/your-repo/your-app" # Update with your repo
  oauth_token    = var.github_token

  build_spec = <<EOF
version: 1.0
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
EOF

  environment_variables = {
    NODE_ENV = "production"
  }
  
  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

# IAM Roles and Policies for API Gateway and Amplify
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api-gateway-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logging_policy" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-logging-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.api_stage.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}
