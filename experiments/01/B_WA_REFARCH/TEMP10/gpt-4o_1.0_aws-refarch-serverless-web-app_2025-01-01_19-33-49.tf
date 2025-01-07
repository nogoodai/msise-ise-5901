terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack for resource names."
  default     = "my-app-stack"
}

variable "cognito_domain_prefix" {
  description = "The prefix for the custom Cognito domain."
  default     = "myapp"
}

resource "aws_cognito_user_pool" "user_pool" {
  name                   = "user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = [
    "ALLOW_AUTH_CODE_FLOW",
    "ALLOW_IMPLICIT_FLOW"
  ]

  o_auth_flows {
    authorization_code_grant = true
    implicit_code_grant      = true
  }

  o_auth_scopes = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for managing to-do items"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  deployment_id = aws_api_gateway_deployment.todo_api_deployment.id

  xray_tracing_enabled = true

  tags = {
    Name        = "prod"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

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
    offset = 0
    period = "DAY"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role-${var.stack_name}"

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
    Name        = "LambdaExecutionRole"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-policy-${var.stack_name}"
  description = "Policy for Lambda to access DynamoDB and CloudWatch."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "AddItemFunction"
    Project     = "todo-app"
  }
}

resource "aws_amplify_app" "frontend" {
  name               = "frontend-${var.stack_name}"
  repository         = "https://github.com/user/repo"
  platform           = "WEB"

  build_spec = <<-EOT
    version: 1.0
    frontend:
      phases:
        preBuild:
          commands:
            - npm install
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: /build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*

  EOT

  environment_variables = {
    NODE_ENV = "production"
  }

  custom_rules {
    source              = "</^[^.]+$|(?<!\\.)/$/>"
    target              = "/index.html"
    status              = "404"
  }

  tags = {
    Name        = "AmplifyFrontend"
    Project     = "todo-app"
  }
}

resource "aws_amplify_branch" "master" {
  app_id     = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "MasterBranch"
    Project     = "todo-app"
  }
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "URL of the API Gateway."
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_url" {
  description = "URL of the Amplify App."
  value       = aws_amplify_app.frontend.default_domain
}
