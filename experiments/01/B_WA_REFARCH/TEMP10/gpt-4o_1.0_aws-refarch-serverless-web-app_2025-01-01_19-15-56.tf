terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Unique stack name for this deployment"
  default     = "prod-stack"
}

variable "git_repository_url" {
  description = "URL of the GitHub repository for Amplify"
  default     = "https://github.com/username/repo"
}

resource "aws_cognito_user_pool" "app_user_pool" {
  name = "user-pool-${var.stack_name}"
  
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "pool_client" {
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
  name         = "user-pool-client"

  generate_secret        = false
  allowed_oauth_flows    = ["code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "pool_domain" {
  domain       = "${var.stack_name}-app-domain"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
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
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "api-gateway-${var.stack_name}"
  description = "API Gateway for todo application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  metrics_enabled = true
  logging_level   = "INFO"
  data_trace_enabled = true

  variables = {
    cognito_user_pool_id = aws_cognito_user_pool.app_user_pool.id
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  triggers = {
    redeployment = sha1(file("${path.module}/api_definition.json"))
  }

  depends_on = [
    aws_api_gateway_rest_api.api_gateway
  ]
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
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

  source_code_hash = filebase64sha256("${path.module}/lambda_function_payload.zip")

  tags = {
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-${var.stack_name}"

  repository = var.git_repository_url
  oauth_token = "YOUR_GITHUB_OAUTH_TOKEN" // Assume it's set in environment variables or another secure method

  build_spec = <<EOF
version: 1
frontend:
  phases:
    build:
      commands:
        - npm install
        - npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
EOF

  tags = {
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"

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

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = "cloudwatch:PutMetricData"
        Effect = "Allow"
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
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_write_logs" {
  name = "api-gateway-write-logs"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.app_user_pool.id
}

output "api_gateway_endpoint" {
  value = aws_api_gateway_rest_api.api_gateway.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
