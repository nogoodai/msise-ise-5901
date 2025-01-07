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
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "project_name" {
  description = "The name of the project."
  default     = "serverless-web-app"
}

variable "stack_name" {
  description = "The stack name for resource separation."
  default     = "prod"
}

variable "github_repo" {
  description = "GitHub repository URL for the Amplify app source."
  default     = "https://github.com/user/repo"
}

variable "cognito_domain_prefix" {
  description = "Custom domain prefix for the Cognito User Pool."
  default     = "auth"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 6
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = false
    require_symbols                  = false
  }

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.project_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "${var.cognito_domain_prefix}-${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

  read_capacity  = 5
  write_capacity = 5

  hash_key = "cognito-username"
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
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name = "${var.project_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api"
    Environment = var.stack_name
    Project     = var.project_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  deployment_id = aws_api_gateway_deployment.prod_deployment.id

  tags = {
    Name        = "prod-stage"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"
  description = "Usage plan for API Gateway"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_stage.prod_stage.stage_name
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
    Name        = "usage-plan"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "todo_lambda" {
  for_each = {
    "add-item"       = "POST /item",
    "get-item"       = "GET /item/{id}",
    "get-all-items"  = "GET /item",
    "update-item"    = "PUT /item/{id}",
    "complete-item"  = "POST /item/{id}/done",
    "delete-item"    = "DELETE /item/{id}"
  }

  function_name = "${var.project_name}-${var.stack_name}-${each.key}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      "DYNAMODB_TABLE" = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.project_name}-${each.key}"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_amplify_app" "frontend" {
  name = "${var.project_name}-frontend"

  repository = var.github_repo
  branch     = "master"
  enable_auto_build = true

  environment_variables = {
    "_NPM_CONFIG_LOGLEVEL" = "warn"
  }

  tags = {
    Name        = "frontend"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-role"

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
    Name        = "${var.project_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "cloudwatch_logs_policy" {
  name = "${var.project_name}-cloudwatch-logs-policy"

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

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.user_pool.id
}

output "api_gateway_url" {
  description = "Base URL for the API Gateway."
  value       = aws_api_gateway_deployment.prod_deployment.invoke_url
}

output "amplify_app_id" {
  description = "The ID of the Amplify app."
  value       = aws_amplify_app.frontend.id
}
