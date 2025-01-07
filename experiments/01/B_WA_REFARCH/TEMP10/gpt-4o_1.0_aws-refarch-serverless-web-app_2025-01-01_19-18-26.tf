terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "stack_name" {
  default = "prod"
}

variable "github_repo" {
  description = "The GitHub repository URL for the Amplify app"
}

resource "aws_cognito_user_pool" "user_pool" {
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
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "user-pool-client-${var.stack_name}"

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_ADMIN_USER_PASSWORD_AUTH"]

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  generate_secret          = false

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "${var.stack_name}-auth"
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
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-gateway-${var.stack_name}"
  description = "Serverless API Gateway for the web app"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id

  tags = {
    Name        = "api-gateway-prod-stage"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
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

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

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

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name   = "api-gateway-policy-${var.stack_name}"
  role   = aws_iam_role.api_gateway_role.id
  policy = data.aws_iam_policy_document.api_gateway_policy.json
}

data "aws_iam_policy_document" "api_gateway_policy" {
  statement {
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_lambda_function" "lambda_function" {
  for_each = toset(["add_item", "get_item", "get_all_items", "update_item", "complete_item", "delete_item"])

  function_name  = "${each.key}-${var.stack_name}"
  handler        = "${each.key}.handler"
  runtime        = "nodejs12.x"
  memory_size    = 1024
  timeout        = 60

  role = aws_iam_role.lambda_exec_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "lambda-${each.key}-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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
    name   = "dynamodb-access-${var.stack_name}"
    policy = data.aws_iam_policy_document.lambda_policy.json
  }

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:GetItem"
    ]

    resources = [aws_dynamodb_table.todo_table.arn]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-app-${var.stack_name}"

  source_code_management {
    repository_url = var.github_repo
  }

  build_spec = <<-EOT
    version: 1.0
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
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

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id     = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "amplify-branch-master-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
