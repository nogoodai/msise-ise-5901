terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "stack_name" {
  default = "my-app"
}

variable "cognito_domain_prefix" {
  default = "myapp"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_symbols   = false
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id         = aws_cognito_user_pool.main.id
  generate_secret      = false
  allowed_oauth_flows  = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

  hash_key  = "cognito-username"
  range_key = "id"

  read_capacity  = 5
  write_capacity = 5

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

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "cognito_auth" {
  name                    = "cognito-authorizer"
  rest_api_id             = aws_api_gateway_rest_api.api.id
  type                    = "COGNITO_USER_POOLS"
  identity_source         = "method.request.header.Authorization"
  provider_arns           = [aws_cognito_user_pool.main.arn]
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format = "$context.identity.sourceIp - $context.identity.caller - $context.requestId - $context.httpMethod - $context.resourcePath - $context.status"
  }

  xray_tracing_enabled = true
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "UsagePlan-${var.stack_name}"

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

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/api-gateway/${var.stack_name}-logs"
  retention_in_days = 7
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  inline_policy {
    name = "DynamoDBAccess"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "dynamodb:GetItem",
            "dynamodb:Query",
            "dynamodb:Scan"
          ]
          Resource = aws_dynamodb_table.todo_table.arn
        },
        {
          Effect = "Allow"
          Action = [
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem"
          ]
          Resource = aws_dynamodb_table.todo_table.arn
        },
        {
          Effect = "Allow"
          Action = [
            "cloudwatch:PutMetricData"
          ]
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  # Assuming source code is loaded from a local path or S3
  filename = "path/to/lambda/code.zip"
}

resource "aws_lambda_function" "get_item" {
  function_name = "get-item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  filename = "path/to/lambda/code.zip"
}

# Add additional lambda functions for other operations (Get All, Update, Complete, Delete)...

resource "aws_amplify_app" "frontend" {
  name                = "${var.stack_name}-frontend"
  repository          = "https://github.com/user/repo"
  build_spec          = file("amplify-build-spec.yml")

  auto_branch_creation {
    enable_auto_build = true
  }

  environment_variables = {
    NODE_ENV = "production"
  }
}

resource "aws_amplify_branch" "master" {
  app_id             = aws_amplify_app.frontend.id
  branch_name        = "master"
  enable_auto_build  = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "api_endpoint" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "amplify_app_url" {
  value = aws_amplify_app.frontend.default_domain
}
