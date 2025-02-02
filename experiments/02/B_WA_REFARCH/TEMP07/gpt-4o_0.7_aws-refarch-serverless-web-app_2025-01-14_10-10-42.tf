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
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for resource naming"
  type        = string
  default     = "prod-stack"
}

variable "github_repository" {
  description = "GitHub repository for Amplify source"
  type        = string
}

resource "aws_cognito_user_pool" "app_user_pool" {
  name = "app-user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "app-user-pool-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-todo-app"
  }
}

resource "aws_cognito_user_pool_client" "app_user_pool_client" {
  user_pool_id               = aws_cognito_user_pool.app_user_pool.id
  name                       = "app-user-pool-client-${var.stack_name}"
  generate_secret            = false
  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "app-user-pool-client-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-todo-app"
  }
}

resource "aws_cognito_user_pool_domain" "app_user_pool_domain" {
  domain       = "${var.stack_name}-custom-domain"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
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
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-todo-app"
  }
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for the serverless todo application"

  endpoint_configuration {
    types = ["EDGE"]
  }

  tags = {
    Name        = "todo-api-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-todo-app"
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.todo_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = "prod"

  xray_tracing_enabled = true

  tags = {
    Name        = "todo-api-stage-prod"
    Environment = "production"
    Project     = "serverless-todo-app"
  }
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  triggers = {
    redeployment = sha1(join("", list(
      aws_lambda_function.add_item.arn,
      aws_lambda_function.get_item.arn,
      aws_lambda_function.get_all_items.arn,
      aws_lambda_function.update_item.arn,
      aws_lambda_function.complete_item.arn,
      aws_lambda_function.delete_item.arn
    )))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name = "todo-usage-plan-${var.stack_name}"

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

  tags = {
    Name        = "todo-usage-plan-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-todo-app"
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "add-item-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-todo-app"
  }
}

# Repeat the above aws_lambda_function resource for get_item, get_all_items, update_item, complete_item, and delete_item with appropriate function names and handlers.

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
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-todo-app"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "xray:PutTraceSegments"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "frontend_app" {
  name                = "frontend-app-${var.stack_name}"
  repository          = var.github_repository
  oauth_token         = "<GITHUB_OAUTH_TOKEN>" # Replace with secure token handling

  build_spec = jsonencode({
    version = "1.0"
    frontend = {
      phases = {
        preBuild = {
          commands = ["npm install"]
        }
        build = {
          commands = ["npm run build"]
        }
      }
      artifacts = {
        baseDirectory = "/build"
        files = ["**/*"]
      }
      cache = {
        paths = ["node_modules/**/*"]
      }
    }
  })

  environment_variables = {
    _LIVE_UPDATES = "[]"
  }

  auto_branch_creation_config {
    patterns = ["master"]
    auto_build = true
  }

  tags = {
    Name        = "frontend-app-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-todo-app"
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.app_user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend_app.id
}
