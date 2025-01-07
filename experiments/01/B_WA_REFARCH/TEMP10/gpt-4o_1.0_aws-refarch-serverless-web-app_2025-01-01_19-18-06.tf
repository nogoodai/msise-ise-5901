terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.2.0"
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

variable "github_repo_url" {
  description = "URL of the GitHub repository for Amplify app source."
}

resource "aws_cognito_user_pool" "auth" {
  name = "user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers = false
    require_symbols = false
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  name                   = "user-pool-client-${var.stack_name}"
  user_pool_id           = aws_cognito_user_pool.auth.id
  generate_secret        = false
  allowed_oauth_flows    = ["code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.auth.id
}

resource "aws_dynamodb_table" "todo" {
  name           = "todo-table-${var.stack_name}"
  hash_key       = "cognito-username"
  range_key      = "id"

  attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  billing_mode = "PROVISIONED"

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for managing to-do items"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
  variables = {
    lambda_alias = "prod"
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

resource "aws_lambda_function" "handler" {
  filename         = "function.zip"
  function_name    = "todo-handler-${var.stack_name}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  publish          = true
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo.name
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "sts:AssumeRole"
      Effect   = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo_policy" {
  policy_arn = aws_iam_policy.dynamodb_crud.arn
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_iam_policy" "dynamodb_crud" {
  name   = "LambdaDynamoDBCrudPolicy-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query"
      ]
      Resource = aws_dynamodb_table.todo.arn
    }]
  })
}

resource "aws_iam_role" "api_gateway" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy_attachment" "api_gateway_logging" {
  name       = "api-gateway-cloudwatch-logs-${var.stack_name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
  roles      = [aws_iam_role.api_gateway.name]
}

resource "aws_amplify_app" "frontend" {
  name  = "amplify-app-${var.stack_name}"
  repository = var.github_repo_url
  oauth_token = data.aws_ssm_parameter.github_token.value

  auto_branch_creation {
    patterns = ["*"]

    basic_auth_credentials = data.aws_ssm_parameter.github_token.value
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "master"

  basic_auth_credentials = data.aws_ssm_parameter.github_token.value
}

data "aws_ssm_parameter" "github_token" {
  name = "/amplify/github/token"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.auth.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
