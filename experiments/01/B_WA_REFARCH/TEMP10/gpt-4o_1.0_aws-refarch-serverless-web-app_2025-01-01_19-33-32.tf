terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = "us-east-1"
}

################################################
# Variables
################################################

variable "stack_name" {
  description = "The stack name for naming resources"
  type        = string
  default     = "myapp"
}

variable "environment" {
  description = "The environment to deploy to"
  type        = string
  default     = "production"
}

variable "github_repository" {
  description = "GitHub repository for Amplify"
  type        = string
  default     = "user/repo"
}

################################################
# Cognito
################################################

resource "aws_cognito_user_pool" "main" {
  name                  = "user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

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
    Project     = "Serverless Web App"
  }
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id       = aws_cognito_user_pool.main.id
  name               = "user-pool-client-${var.stack_name}"
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows  = ["ALLOW_AUTH_CODE_FLOW", "ALLOW_IMPLICIT_FLOW"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  tags = {
    Name        = "cognito-user-pool-client-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain          = "${var.stack_name}.auth.${data.aws_region.current.name}.amazoncognito.com"
  user_pool_id    = aws_cognito_user_pool.main.id

  tags = {
    Name        = "cognito-user-pool-domain-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

################################################
# DynamoDB
################################################

resource "aws_dynamodb_table" "todo" {
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
    Name        = "dynamodb-table-todo-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

################################################
# API Gateway
################################################

resource "aws_api_gateway_rest_api" "main" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": "*",
        "Action": "execute-api:Invoke",
        "Resource": "arn:aws:execute-api:*:*:*"
      }
    ]
  }
EOF

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  name                    = "CognitoAuthorizer"
  rest_api_id             = aws_api_gateway_rest_api.main.id
  type                    = "COGNITO_USER_POOLS"
  provider_arns           = [aws_cognito_user_pool.main.arn]
  identity_source         = "method.request.header.Authorization"
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
  variables = {
    lambdaAlias = aws_lambda_alias.main.name
  }

  tags = {
    Name        = "api-stage-prod-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
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
    Project     = "Serverless Web App"
  }
}

################################################
# Lambda
################################################

resource "aws_iam_role" "lambda_execution" {
  name = "lambda-execution-${var.stack_name}"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
EOF

  tags = {
    Name        = "lambda-execution-role-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        "Resource": "${aws_dynamodb_table.todo.arn}"
      },
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:*:*:*"
      }
    ]
  }
EOF
}

resource "aws_lambda_function" "main" {
  function_name = "lambda-function-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_execution.arn

  memory_size = 1024
  timeout     = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo.name
    }
  }

  tags = {
    Name        = "lambda-function-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

################################################
# Amplify
################################################

resource "aws_amplify_app" "main" {
  name  = "amplify-app-${var.stack_name}"
  repository = "https://github.com/${var.github_repository}"

  build_spec = <<EOF
version: 1.0
backend:
  phases:
    build:
      commands:
        - amplifyPush --simple
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: out
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*

EOF

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

resource "aws_amplify_branch" "main" {
  branch_name = "master"
  app_id      = aws_amplify_app.main.id

  stage = "PRODUCTION"

  tags = {
    Name        = "amplify-branch-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

################################################
# IAM Roles and Policies
################################################

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "apigateway.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
EOF

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_policy" "api_gateway_policy" {
  name = "api-gateway-policy-${var.stack_name}"

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "logs:*",
        "Resource": "*"
      }
    ]
  }
EOF
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "amplify.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
EOF

  tags = {
    Name        = "amplify-role-${var.stack_name}"
    Environment = var.environment
    Project     = "Serverless Web App"
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_iam_policy" "amplify_policy" {
  name = "amplify-policy-${var.stack_name}"

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "amplify:*",
        "Resource": "*"
      }
    ]
  }
EOF
}

################################################
# Outputs
################################################

output "user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool"
}

output "api_gateway_url" {
  value       = aws_api_gateway_rest_api.main.execution_arn
  description = "The URL of the API Gateway"
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.todo.arn
  description = "The ARN of the DynamoDB table"
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify App"
}

output "lambda_function_arn" {
  value       = aws_lambda_function.main.arn
  description = "The ARN of the Lambda function"
}
