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
  default = "us-east-1"
}

variable "stack_name" {
  description = "The name of the application stack"
}

variable "project" {
  default = "serverless-web-app"
}

# Cognito
resource "aws_cognito_user_pool" "app_user_pool" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.project
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
  explicit_auth_flows   = ["ALLOW_ADMIN_USER_PASSWORD_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  oauth {
    flows = ["code", "implicit"]
    scopes = ["email", "phone", "openid"]
  }

  generate_secret = false

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.project
  }
}

resource "aws_cognito_user_pool_domain" "app_domain" {
  domain     = "${var.stack_name}-${var.project}"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
}

# DynamoDB
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.project
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "app_api" {
  name        = "${var.stack_name}-api"
  description = "API for the serverless web application"

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.project
  }
}

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.app_api.id
  parent_id   = aws_api_gateway_rest_api.app_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "add_item" {
  rest_api_id   = aws_api_gateway_rest_api.app_api.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = var.authorizer_id
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_exec_role.arn

  tracing_config {
    mode = "Active"
  }

  publish = true

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = var.project
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = {
    Environment = var.stack_name
    Project     = var.project
  }
}

resource "aws_iam_policy" "dynamodb_lambda_policy" {
  name = "${var.stack_name}-dynamodb-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
          "xray:PutTelemetryRecords",
          "xray:PutTraceSegments"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "attach_dynamodb_lambda_policy" {
  name       = "attach-${var.stack_name}-dynamodb-lambda-policy"
  policy_arn = aws_iam_policy.dynamodb_lambda_policy.arn
  roles      = [aws_iam_role.lambda_exec_role.name]
}

# Amplify
resource "aws_amplify_app" "frontend" {
  name                = "${var.stack_name}-amplify"
  repository          = "https://github.com/${var.github_repo}"
  branch              = "master"

  build_spec = <<EOF
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
    baseDirectory: build
    files:
      - '**/*'
EOF

  environment_variables = {
    "_LIVE_UPDATES" = "[{ \"packageManager\": \"npm\" }]"
  }

  auto_branch_creation_config {
    patterns = ["master"]
  }

  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.project
  }
}

resource "aws_amplify_branch" "main" {
  app_id = aws_amplify_app.frontend.id
  branch_name = "master"

  enable_auto_build = true

  tags = {
    Name        = "${var.stack_name}-amplify-branch"
    Environment = var.stack_name
    Project     = var.project
  }
}

output "user_pool_id" {
  value = aws_cognito_user_pool.app_user_pool.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.app_api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
