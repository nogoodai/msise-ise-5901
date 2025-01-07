terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default     = "us-east-1"
  description = "The AWS region to deploy the resources"
}

variable "stack_name" {
  description = "The name of the application stack"
  type        = string
}

variable "git_repository" {
  description = "The GitHub repository for the frontend application"
  type        = string
}

variable "git_branch" {
  description = "The branch to deploy from in the GitHub repository"
  default     = "master"
}

variable "environment" {
  description = "The environment for tagging purposes"
  default     = "production"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_symbols   = false
    require_numbers   = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.stack_name}-app-client"

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH"]

  o_auth {
    flows = {
      authorization_code_grant = true
      implicit                 = true
    }
    scopes = ["email", "openid", "phone"]
  }

  generate_secret = false

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "${var.stack_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

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
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = jsonencode({
      requestId       = "$context.requestId"
      ip              = "$context.identity.sourceIp"
      caller          = "$context.identity.caller"
      user            = "$context.identity.user"
      requestTime     = "$context.requestTime"
      httpMethod      = "$context.httpMethod"
      resourcePath    = "$context.resourcePath"
      status          = "$context.status"
      protocol        = "$context.protocol"
      responseLength  = "$context.responseLength"
    })
  }

  tags = {
    Name        = "${var.stack_name}-api-stage"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_api_gateway_integration.add_item]
}

resource "aws_api_gateway_method" "any_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_rest_api.api.root_resource_id
  http_method   = "ANY"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "CognitoAuthorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  type          = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_integration" "add_item" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_rest_api.api.root_resource_id
  http_method             = aws_api_gateway_method.any_method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.add_item.invoke_arn
}

resource "aws_lambda_function" "add_item" {
  filename         = "functions/add_item.zip"
  function_name    = "${var.stack_name}-add-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/apigateway/${var.stack_name}-access-logs"
  retention_in_days = 14

  tags = {
    Name        = "${var.stack_name}-api-logs"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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
    Name        = "${var.stack_name}-lambda-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
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
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_amplify_app" "frontend" {
  name              = "${var.stack_name}-frontend"
  repository        = var.git_repository
  enable_auto_branch_creation = true

  build_spec = <<EOF
version: 1
frontend:
  phases:
    build:
      commands:
        - yarn install
        - yarn build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  oauth_token = data.aws_ssm_parameter.github_token.value

  tags = {
    Name        = "${var.stack_name}-frontend"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "main_branch" {
  app_id     = aws_amplify_app.frontend.id
  branch_name = var.git_branch
  enable_auto_build = true

  tags = {
    Name        = "${var.stack_name}-frontend-${var.git_branch}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

data "aws_iam_policy_document" "amplify_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["amplify.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = data.aws_iam_policy_document.amplify_assume_role_policy.json

  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "amplify:*"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_endpoint" {
  value = "${aws_api_gateway_rest_api.api.endpoint_configuration.0.types}/prod"
}

output "amplify_app_url" {
  value = aws_amplify_app.frontend.default_domain
}
