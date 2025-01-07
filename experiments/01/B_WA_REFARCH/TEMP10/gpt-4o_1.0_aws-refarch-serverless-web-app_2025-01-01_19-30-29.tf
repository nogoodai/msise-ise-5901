terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  default     = "us-east-1"
  description = "The AWS region to deploy in."
}

variable "application_name" {
  description = "The name of the application."
  default     = "serverless-web-app"
}

variable "stack_name" {
  description = "The stack name for resource naming."
  default     = "dev"
}

variable "github_repository" {
  description = "The GitHub repository to use for Amplify."
}

variable "github_oauth_token" {
  description = "OAuth token for GitHub access."
  sensitive   = true
}

variable "amplify_branch" {
  description = "Amplify branch for deployment."
  default     = "master"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false

  tags = {
    Name        = "${var.application_name}-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-domain"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_dynamodb_table" "todo" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity = 5
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
    Name        = "todo-table"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    actions = ["dynamodb:*"]
    resources = [aws_dynamodb_table.todo.arn]
  }
}

resource "aws_iam_role" "lambda_execution" {
  name = "${var.application_name}-lambda-exec-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid = ""
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.application_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

resource "aws_lambda_function" "api_handler" {
  function_name = "${var.application_name}-api-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_execution.arn

  memory_size = 1024
  timeout     = 60

  environment {
    variables = {
      TODO_TABLE = aws_dynamodb_table.todo.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-lambda"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "item_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "item_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_method.item_get,
    aws_api_gateway_method.item_post
  ]
  
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"
  
  tags = {
    Name        = "${var.application_name}-deployment"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.application_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_deployment.main.stage_name
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
    Name        = "${var.application_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role" "apigateway_logs" {
  name = "${var.application_name}-api-gateway-log-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
        Sid = ""
      }
    ]
  })
  
  tags = {
    Name        = "${var.application_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "apigateway_log_policy" {
  name = "${var.application_name}-api-gateway-log-policy"
  role = aws_iam_role.apigateway_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:*"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "app" {
  name = "${var.application_name}-amplify-app"
  
  repository = var.github_repository
  
  oauth_token = var.github_oauth_token
  
  environment_variables = {
    NODE_ENV = "production"
  }
  
  build_spec = <<-EOT
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
      baseDirectory: /build
      files:
        - '**/*'
    cache:
      paths:
        - node_modules/**/*
  EOT
  
  tags = {
    Name        = "${var.application_name}-amplify"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "branch" {
  app_id = aws_amplify_app.app.id
  branch_name = var.amplify_branch
  enable_auto_build = true
  
  tags = {
    Name        = "${var.application_name}-amplify-branch"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.main.id
}

output "api_gateway_url" {
  description = "The URL of the API Gateway."
  value       = aws_api_gateway_deployment.main.invoke_url
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.todo.name
}

output "amplify_app_id" {
  description = "The ID of the Amplify App."
  value       = aws_amplify_app.app.id
}
