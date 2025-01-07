terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy resources"
}

variable "project_name" {
  type        = string
  default     = "serverless-web-app"
  description = "Project name used for naming resources"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment (e.g., dev, staging, prod)"
}

variable "stack_name" {
  type        = string
  default     = "main"
  description = "Stack name to differentiate resources"
}

variable "cognito_domain" {
  type        = string
  default     = "auth"
  description = "Cognito custom domain prefix"
}

variable "github_repo" {
  type        = string
  default     = "username/repository"
  description = "GitHub repository for Amplify"
}

provider "aws" {
  region = var.region
}

# Networking resources
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name        = "${var.project_name}-public-subnet"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Authentication resources
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.project_name}-${var.stack_name}-user-pool-client"

  user_pool_id        = aws_cognito_user_pool.main.id
  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.cognito_domain}-${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.project_name}-user-pool-domain"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Database resources
resource "aws_dynamodb_table" "todo" {
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
    Name        = "${var.project_name}-todo-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway resources
resource "aws_api_gateway_rest_api" "main" {
  name = "${var.project_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api-gateway"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "${var.project_name}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.main.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.main.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body))
  }

  tags = {
    Name        = "${var.project_name}-api-gateway-deployment"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name        = "${var.project_name}-api-usage-plan"
  description = "Usage plan for ${var.project_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_deployment.main.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.project_name}-api-usage-plan"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda functions
locals {
  lambda_functions = [
    { name = "add-item", method = "POST", path = "/item", action = "create" },
    { name = "get-item", method = "GET", path = "/item/{id}", action = "read" },
    { name = "get-all-items", method = "GET", path = "/item", action = "read" },
    { name = "update-item", method = "PUT", path = "/item/{id}", action = "update" },
    { name = "complete-item", method = "POST", path = "/item/{id}/done", action = "update" },
    { name = "delete-item", method = "DELETE", path = "/item/{id}", action = "delete" }
  ]
}

resource "aws_lambda_function" "todo_functions" {
  for_each = { for func in local.lambda_functions : func.name => func }

  function_name = "${var.project_name}-${each.value.name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  filename      = "lambda_function_payload.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${each.value.name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM roles and policies
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

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
    Name        = "${var.project_name}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-api-gateway-role"

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
    Name        = "${var.project_name}-api-gateway-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-amplify-role"

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
    Name        = "${var.project_name}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_service" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
}

# Amplify resources
resource "aws_amplify_app" "main" {
  name       = "${var.project_name}-app"
  repository = var.github_repo

  build_spec = <<-EOT
    version: 0.1
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
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
  EOT

  environment_variables = {
    ENV = var.environment
  }

  tags = {
    Name        = "${var.project_name}-amplify-app"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
  framework   = "React"
  stage       = "PRODUCTION"

  tags = {
    Name        = "${var.project_name}-amplify-branch"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Monitoring and alerting
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.main.name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-api-gateway-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = "${var.project_name}-add-item"
  }

  tags = {
    Name        = "${var.project_name}-lambda-errors-alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Outputs
output "api_gateway_url" {
  value       = aws_api_gateway_deployment.main.invoke_url
  description = "API Gateway URL"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "Cognito User Pool ID"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "Cognito User Pool Client ID"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "Cognito Domain"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo.name
  description = "DynamoDB Table Name"
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "Amplify App ID"
}

output "amplify_branch_url" {
  value       = aws_amplify_branch.main.custom_domain
  description = "Amplify Branch URL"
}
