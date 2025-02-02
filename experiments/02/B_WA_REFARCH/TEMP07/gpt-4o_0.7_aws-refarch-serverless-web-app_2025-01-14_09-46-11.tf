terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Stack name for resource naming"
  default     = "myapp"
}

variable "email_verification_message" {
  description = "Email verification message for Cognito"
  default     = "Welcome to our app. Your verification code is {####}"
}

variable "github_oauth_token" {
  description = "GitHub OAuth token for Amplify"
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length                   = 6
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = false
    require_symbols                  = false
  }

  email_verification_message = var.email_verification_message
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "client-${var.stack_name}"

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "openid", "phone"]
  allowed_oauth_flows_user_pool_client = true

  explicit_auth_flows        = ["ALLOW_REFRESH_TOKEN_AUTH"]

  generate_secret            = false
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain = "${var.stack_name}-auth"
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

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  provisioned_throughput {
    read_capacity_units  = 5
    write_capacity_units = 5
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  provider {
    region = var.region
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.api.id
  deployment_id        = aws_api_gateway_deployment.api_deployment.id

  xray_tracing_enabled = true

  variables = {
    cognito_user_pool = aws_cognito_user_pool.user_pool.id
  }

  tags = {
    Name        = "api-stage-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
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

resource "aws_lambda_function" "crud_lambda" {
  for_each = {
    "add_item"       = jsonencode({ method = "POST", path = "/item" }),
    "get_item"       = jsonencode({ method = "GET", path = "/item/{id}" }),
    "get_all_items"  = jsonencode({ method = "GET", path = "/item" }),
    "update_item"    = jsonencode({ method = "PUT", path = "/item/{id}" }),
    "complete_item"  = jsonencode({ method = "POST", path = "/item/{id}/done" }),
    "delete_item"    = jsonencode({ method = "DELETE", path = "/item/{id}" })
  }

  function_name = "${each.key}-function-${var.stack_name}"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
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
    Name        = "${each.key}-lambda-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
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
      }
    ]
  })

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
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
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-app-${var.stack_name}"

  repository = var.github_repo

  oauth_token = var.github_oauth_token

  auto_branch_creation_config {
    enable_auto_build = true
  }

  build_spec = file("amplify-buildspec.yml")

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.api_stage.invoke_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}
