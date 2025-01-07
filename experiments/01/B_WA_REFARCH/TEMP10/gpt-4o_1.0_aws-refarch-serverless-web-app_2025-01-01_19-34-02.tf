terraform {
  required_providers {
    aws = "= 5.1.0"
  }
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
  description = "The name of the stack to distinguish resources"
  type        = string
  default     = "prod-stack"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = [
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  callback_urls = ["https://example.com/callback"]

  allowed_oauth_flows            = ["code", "implicit"]
  allowed_oauth_scopes           = ["email", "phone", "openid"]
  generate_secret                = false
  supported_identity_providers   = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain         = "${var.stack_name}-auth"
  user_pool_id   = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "table" {
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

  tags = {
    Environment = var.stack_name
    Project     = "TodoApp"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for the serverless application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Environment = var.stack_name
    Project     = "TodoApp"
  }
}

resource "aws_api_gateway_stage" "stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id

  tags = {
    Environment = var.stack_name
    Project     = "TodoApp"
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename         = "add_item.zip"
  function_name    = "${var.stack_name}-add-item"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.add_item"
  runtime          = "nodejs12.x"

  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.table.name
    }
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec" {
  name               = "${var.stack_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_attach_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.stack_name}-lambda-policy"
  role   = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:Query",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.table.arn
      }
    ]
  })
}

# Amplify App for Frontend Hosting
resource "aws_amplify_app" "amplify" {
  name                 = "${var.stack_name}-frontend"
  repository           = "https://github.com/example/repo"

  build_spec           = <<EOF
version: 1
backend:
  phases:
    build:
      commands:
        - amplifyPush --simple
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths: []
EOF

  environment_variables = {
    ENV_VAR = "value"
  }
}

resource "aws_amplify_branch" "master" {
  app_id     = aws_amplify_app.amplify.id
  branch_name = "master"
  enable_auto_build = true
}

output "user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "lambda_function_name" {
  value = aws_lambda_function.add_item.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify.id
}
