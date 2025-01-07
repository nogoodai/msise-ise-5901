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
  default = "my-stack"
}

variable "email_username" {
  default = true
}

variable "password_length" {
  default = 6
}

variable "require_uppercase" {
  default = true
}

variable "require_lowercase" {
  default = true
}

variable "build_spec" {
  default = <<EOF
version: 0.2
phases:
  install:
    runtime-versions:
      nodejs: 12
    commands:
      - npm install
  build:
    commands:
      - npm run build
artifacts:
  files:
    - '**/*'
  base-directory: build
EOF
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = var.password_length
    require_uppercase = var.require_uppercase
    require_lowercase = var.require_lowercase
    require_symbols   = false
    require_numbers   = false
  }

  tags = {
    Name        = "cognito-user-pool-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id                  = aws_cognito_user_pool.user_pool.id
  name                          = "${var.stack_name}-app-client"
  generate_secret               = false
  allowed_oauth_flows          = ["code", "implicit"]
  allowed_oauth_scopes         = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "cognito-user-pool-client-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

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
    Name        = "dynamodb-table-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  xray_tracing_enabled = true

  deployment_id = aws_api_gateway_deployment.api_gateway_deployment.id

  tags = {
    Name        = "api-stage-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan"

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  tags = {
    Name        = "api-usage-plan-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id

    stage = aws_api_gateway_stage.api_stage.stage_name
  }
}

resource "aws_lambda_function" "add_item_function" {
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  xray_tracing_mode = "Active"

  tags = {
    Name        = "lambda-add-item-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

# Repeat Lambda function resource creation for each required operation:
# get_item_function, get_all_items_function, update_item_function,
# complete_item_function, delete_item_function.

resource "aws_amplify_app" "amplify_app" {
  name      = var.stack_name
  repository = "https://github.com/user/repo"

  branch {
    branch_name = "master"
    enable_auto_build = true
  }

  build_spec = var.build_spec

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": { "Service": "apigateway.amazonaws.com" },
        "Effect": "Allow"
      }
    ]
  })

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        "Resource": "*"
      }
    ]
  })
}

# Repeat IAM role and policy creation for other components as specified.

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB Table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "Invoke URL of the API Gateway"
  value       = aws_api_gateway_deployment.api_gateway_deployment.invoke_url
}

output "amplify_app_id" {
  description = "ID of the Amplify App"
  value       = aws_amplify_app.amplify_app.id
}
