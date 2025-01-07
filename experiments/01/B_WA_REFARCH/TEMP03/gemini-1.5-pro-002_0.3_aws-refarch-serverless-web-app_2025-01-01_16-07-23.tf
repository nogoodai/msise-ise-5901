terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type    = string
  default = "https://github.com/example/todo-app"
}

variable "github_repo_branch" {
  type    = string
  default = "main"
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  username_attributes = ["email"]

  verification_message_template {
    default_email_options {
      email_message = "Your verification code is {####}"
      email_subject = "Welcome to ${var.application_name}"
    }
  }

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }

 email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
    source_arn = "arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:identity/ses.amazonaws.com"
  }

  auto_verified_attributes = ["email"]
}

data "aws_caller_identity" "current" {}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain      = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls = ["http://localhost:3000/"] # Replace with your frontend URL
  logout_urls   = ["http://localhost:3000/"] # Replace with your frontend URL

  supported_identity_providers = ["COGNITO"]
}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
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
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}


# IAM Policy for Lambda (DynamoDB Access)
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda_dynamodb_policy_${var.stack_name}"
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem",
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Effect = "Allow",
        Resource = "*"
      },
    ]
  })
}

# Attach Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


# Lambda Functions (Placeholder - Replace with your actual Lambda code)
resource "aws_lambda_function" "add_item" {
  function_name = "add_item_${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60

  # Replace with your actual Lambda code
  filename      = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")

  tracing_config {
    mode = "Active"
  }
}

# Example for other Lambda functions - repeat for each function
resource "aws_lambda_function" "get_item" {
  function_name = "get_item_${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60

  # Replace with your actual Lambda code
  filename      = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")

  tracing_config {
    mode = "Active"
  }
}


# API Gateway - REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
}

# API Gateway - Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id  = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# API Gateway - Resource and Methods (Example for /item)
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

# API Gateway - Integration (Example for POST /item)
resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.post_item.http_method
  integration_type        = "aws_proxy"
  integration_http_method = "POST"
  integration_uri         = aws_lambda_function.add_item.invoke_arn
}


# API Gateway - Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

 depends_on = [
    aws_api_gateway_integration.post_item_integration, # Add all integrations here
  ]
}

# API Gateway - Stage
resource "aws_api_gateway_stage" "prod" {
  stage_name        = "prod"
  rest_api_id      = aws_api_gateway_rest_api.main.id
  deployment_id    = aws_api_gateway_deployment.main.id
}


# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo_url
  access_token = var.github_access_token # Add this variable for GitHub access

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
  cache:
    paths:
      - node_modules/**/*
EOF
}

variable "github_access_token" {
  type = string
  description = "GitHub Personal Access Token"
}


# Amplify Branch (Master/Main)
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}


# IAM Role for API Gateway Logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api_gateway_cloudwatch_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

# IAM Policy for API Gateway Logging
resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
  name = "api_gateway_cloudwatch_policy_${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Attach Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
 role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}

# API Gateway Account - Enable CloudWatch Logs
resource "aws_api_gateway_account" "main" {
 cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
}


# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.main.rest_api_id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


