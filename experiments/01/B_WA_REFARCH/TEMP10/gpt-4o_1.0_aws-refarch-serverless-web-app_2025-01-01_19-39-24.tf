terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy the resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Unique stack name for resource naming"
}

variable "github_repository" {
  description = "GitHub repository for the Amplify app source"
}

# Cognito
resource "aws_cognito_user_pool" "main" {
  name = "user-pool-${var.stack_name}"

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
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id          = aws_cognito_user_pool.main.id
  name                  = "user-pool-client-${var.stack_name}"
  generate_secret       = false
  allowed_oauth_flows   = ["authorization_code", "implicit"]
  allowed_oauth_scopes  = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB
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
    read_capacity_units  = 5
    write_capacity_units = 5
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "todo-api-${var.stack_name}"
  description = "API Gateway for todo application"

  tags = {
    Name        = "todo-api-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = "prod"

  tags = {
    Name        = "prod-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name        = "todo-usage-${var.stack_name}"
  description = "Usage plan for todo API"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
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

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  source_code_hash = filebase64sha256("lambda/add_item.zip")
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-${var.stack_name}"
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
    Name        = "lambda-exec-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "dynamodb_policy" {
  name        = "lambda-dynamodb-policy-${var.stack_name}"
  description = "Policy for Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action   = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.dynamodb_policy.arn
}

resource "aws_cloudwatch_log_group" "lambda_log" {
  name              = "/aws/lambda/${var.stack_name}"
  retention_in_days = 14
}

resource "aws_amplify_app" "frontend" {
  name              = "amplify-${var.stack_name}"
  repository        = var.github_repository
  build_spec        = file("buildspec.yml")

  oauth_token       = var.github_oauth_token

  tags = {
    Name        = "amplify-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_amplify_branch" "master" {
  app_id            = aws_amplify_app.frontend.id
  branch_name       = "master"
  enable_auto_build = true

  tags = {
    Name        = "amplify-branch-master-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.add_item.arn
}
