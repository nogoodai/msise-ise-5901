terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "stack_name" {
  default = "myapp"
}

variable "environment" {
  default = "production"
}

variable "project" {
  default = "serverless-web-app"
}

data "aws_caller_identity" "current" {}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }

  tags = {
    Name      = "user-pool-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]

  oauth {
    flows  = ["authorization_code", "implicit"]
    scopes = ["email", "phone", "openid"]
  }

  generate_secret = false

  tags = {
    Name      = "user-pool-client-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name      = "user-pool-domain-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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
    Name      = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for ${var.project}"

  tags = {
    Name      = "api-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  tags = {
    Name      = "api-stage-prod-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
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
    Name      = "usage-plan-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "crud_lambda" {
  for_each     = jsondecode(file("lambda_functions.json"))
  
  function_name = each.key
  handler       = each.value.handler
  runtime       = "nodejs12.x"

  memory_size = 1024
  timeout     = 60

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name      = "lambda-${each.key}-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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

  tags = {
    Name      = "lambda-exec-role-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"
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
        Action   = ["dynamodb:Scan", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })

  tags = {
    Name      = "lambda-policy-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_amplify_app" "frontend" {
  name  = "amplify-app-${var.stack_name}"

  source_code_provider {
    github {
      owner = "your-github-user"
      repository = "your-github-repo"
      oauth_token = var.github_token
    }
  }

  build_spec = file("buildspec.yml")

  tags = {
    Name      = "amplify-app-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_amplify_branch" "frontend_branch" {
  app_id     = aws_amplify_app.frontend.id
  branch_name = "master"

  enable_auto_build = true

  tags = {
    Name      = "amplify-branch-master-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

variable "github_token" {
  description = "Oauth Token for GitHub repository access."
  sensitive   = true
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value       = aws_api_gateway_stage.api_stage.invoke_url
  description = "The URL of the API Gateway stage"
}

output "amplify_app_url" {
  value       = aws_amplify_app.frontend.default_domain
  description = "The URL of the Amplify Frontend"
}
