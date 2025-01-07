terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to create resources in"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the application stack"
  default     = "my-stack"
}

variable "project_name" {
  description = "The name of the project for tagging"
  default     = "serverless-web-app"
}

data "aws_caller_identity" "current" {}

locals {
  cognito_user_pool_name       = "${var.project_name}-user-pool"
  cognito_user_pool_client     = "${var.project_name}-user-pool-client"
  dynamodb_table_name          = "todo-table-${var.stack_name}"
  api_gateway_name             = "${var.project_name}-api"
  amplify_app_name             = "${var.project_name}-frontend"
  amplify_branch_name          = "master"
  cognito_domain               = "${var.project_name}-${var.stack_name}"
  email_tag                    = "my-email@domain.com"
}

resource "aws_cognito_user_pool" "main" {
  name = local.cognito_user_pool_name

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = local.cognito_user_pool_name
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = local.cognito_user_pool_client
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_AUTH_CODE_FLOW", "ALLOW_IMPLICIT_FLOW"]

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = local.cognito_user_pool_client
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = local.cognito_domain
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name         = local.dynamodb_table_name
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
    Name        = local.dynamodb_table_name
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = local.api_gateway_name
  description = "API Gateway for the serverless web application"

  endpoint_configuration {
    types = ["EDGE"]
  }

  minimum_compression_size = 512

  tags = {
    Name        = local.api_gateway_name
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = "$context.requestId - $context.identity.sourceIp - $context.authorizer.principalId"
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${local.api_gateway_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttling_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "crud" {
  function_name = "${var.project_name}-crud"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  code {
    s3_bucket = var.lambda_code_bucket
    s3_key    = var.lambda_code_key
  }

  tags = {
    Name        = "${var.project_name}-crud"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-exec-role"

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
    Name        = "${var.project_name}-lambda-exec-role"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.project_name}-lambda-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Action   = "logs:*"
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = "xray:PutTelemetryRecords"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "frontend" {
  name       = local.amplify_app_name
  repository = "https://github.com/example/my-repo"

  build_spec = <<EOF
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /public
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*

EOF

  tags = {
    Name        = local.amplify_app_name
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = local.amplify_branch_name

  enable_auto_build = true

  tags = {
    Name        = "${local.amplify_app_name}-${local.amplify_branch_name}"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  inline_policy {
    name = "logPolicy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [{
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ],
        Effect   = "Allow",
        Resource = "*"
      }]
    })
  }

  tags = {
    Name        = "${var.project_name}-api-gateway-role"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name = "/aws/apigateway/${var.project_name}"
  retention_in_days = 30
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
  description = "Invoke URL for the API Gateway"
  value       = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_url" {
  description = "URL of the deployed Amplify application"
  value       = aws_amplify_app.frontend.default_domain
}
