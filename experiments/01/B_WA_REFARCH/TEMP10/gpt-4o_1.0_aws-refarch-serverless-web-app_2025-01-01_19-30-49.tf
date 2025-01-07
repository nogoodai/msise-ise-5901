terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "us-east-1"
}

# Variables
variable "application_name" {
  default = "serverless-web-app"
}

variable "stack_name" {
  default = "prod"
}

variable "github_repo_url" {
  description = "GitHub repository URL for Amplify"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "app_user_pool" {
  name          = "${var.application_name}-user-pool"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
  name         = "${var.application_name}-client"
  prevent_user_existence_errors = "ENABLED"
  generate_secret = false

  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["phone", "email", "openid"]
}

resource "aws_cognito_user_pool_domain" "app_domain" {
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
  domain       = "${var.application_name}-${var.stack_name}"
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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api"
  description = "API for ${var.application_name} application"
  
  tags = {
    Name        = var.application_name
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_stage" "apis_stage" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  xray_tracing_enabled = true
}

resource "aws_api_gateway_usage_plan" "api_plan" {
  name = "${var.application_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.apis_stage.stage_name
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
    Name        = "${var.application_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item_function" {
  function_name = "AddItemFunction"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMO_DB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "AddItemFunction"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Additional Lambda Functions should be added for each API operation with similar configuration

# CloudWatch IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

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

  inline_policy {
    name = "api-gateway-cloudwatch-logs-policy"
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

  tags = {
    Name        = "api-gateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify App
resource "aws_amplify_app" "frontend" {
  name              = "${var.application_name}-frontend"
  repository        = var.github_repo_url
  
  build_spec        = file("amplify-buildspec.yml") # Assuming you have a file called amplify-buildspec.yml with the build instructions

  iam_service_role  = aws_iam_role.amplify_role.arn

  environment_variables = {
    NODE_ENV = "production"
  }

  tags = {
    Name        = "${var.application_name}-frontend"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id       = aws_amplify_app.frontend.id
  branch_name  = "master"
  enable_auto_build = true
  
  tags = {
    Name        = "master-branch"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-amplify-role"

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
    Name        = "amplify-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.application_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name = "lambda-dynamodb-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }]
    })
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.app_user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_endpoint" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
