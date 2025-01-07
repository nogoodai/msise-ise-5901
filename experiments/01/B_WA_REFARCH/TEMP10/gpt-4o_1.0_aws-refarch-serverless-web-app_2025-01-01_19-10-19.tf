terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.1.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Stack name to ensure unique resource naming"
  type        = string
  default     = "my-stack"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "github_repository" {
  description = "GitHub repository for the Amplify app source"
  type        = string
}

variable "github_branch" {
  description = "Branch name for Amplify deployments"
  type        = string
  default     = "master"
}

variable "cognito_custom_domain" {
  description = "Custom domain prefix for Cognito User Pool"
  type        = string
  default     = "auth"
}

resource "aws_cognito_user_pool" "main" {
  name                = "user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "cognito-user-pool-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "app" {
  user_pool_id      = aws_cognito_user_pool.main.id
  name              = "user-pool-client-${var.stack_name}"
  generate_secret   = false
  o_auth_flows      = ["code", "implicit"]
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_o_auth_scopes = ["email", "phone", "openid"]

  tags = {
    Name        = "cognito-user-pool-client-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "custom" {
  domain       = "${var.cognito_custom_domain}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

  attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  hash_key  = "cognito-username"
  range_key = "id"

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "dynamodb-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name = "api-${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = var.environment
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.api_deploy.id

  tags = {
    Name        = "api-stage-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
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

  tags = {
    Name        = "usage-plan-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "cognito-authorizer"
  type                   = "COGNITO_USER_POOLS"
  rest_api_id            = aws_api_gateway_rest_api.main.id
  identity_source        = "method.request.header.Authorization"
  provider_arns          = [aws_cognito_user_pool.main.arn]
}

resource "aws_lambda_function" "crud_handler" {
  for_each = {
    "add-item"      = "POST /item",
    "get-item"      = "GET /item/{id}",
    "get-all-items" = "GET /item",
    "update-item"   = "PUT /item/{id}",
    "complete-item" = "POST /item/{id}/done",
    "delete-item"   = "DELETE /item/{id}"
  }

  function_name = "${each.key}-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMO_TABLE = aws_dynamodb_table.todo.name
    }
  }

  tags = {
    Name        = "lambda-function-${each.key}-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each = aws_lambda_function.crud_handler

  name              = "/aws/lambda/${each.key}-${var.stack_name}"
  retention_in_days = 7

  tags = {
    Name        = "log-group-${each.key}-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_amplify_app" "frontend" {
  name               = "amplify-app-${var.stack_name}"
  repository         = var.github_repository

  environment_variables = {
    "AMPLIFY_MONOREPO_APP_ROOT" = "/frontend"
  }

  build_spec = file("${path.module}/buildspec.yml")

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "main" {
  app_id                = aws_amplify_app.frontend.id
  branch_name           = var.github_branch
  enable_auto_build     = true

  tags = {
    Name        = "amplify-branch-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "api_gateway" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "amplify" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "amplify-role-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda" {
  name = "lambda-execution-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "lambda-role-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "api_gateway_logs" {
  name = "api-gateway-logs-policy-${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_access" {
  name = "lambda-dynamodb-access-policy-${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:WriteItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.todo.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "api_gateway_policy_attach" {
  name       = "api-gateway-policy-attach"
  policy_arn = aws_iam_policy.api_gateway_logs.arn
  roles      = [aws_iam_role.api_gateway.name]
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  policy_arn = aws_iam_policy.lambda_dynamodb_access.arn
  role       = aws_iam_role.lambda.name
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.app.id
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB Table"
  value       = aws_dynamodb_table.todo.arn
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = aws_api_gateway_deployment.api_deploy.invoke_url
}

output "amplify_app_id" {
  description = "ID of the Amplify App"
  value       = aws_amplify_app.frontend.id
}
