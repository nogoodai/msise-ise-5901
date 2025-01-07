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
  description = "The AWS region to deploy to."
  default     = "us-west-2"
}

variable "stack_name" {
  description = "The stack name for resource naming."
  default     = "my-stack"
}

variable "amplify_source_repo" {
  description = "The GitHub repository URL for Amplify app."
  default     = "https://github.com/example/repo"
}

resource "aws_cognito_user_pool" "app_user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

resource "aws_cognito_user_pool_client" "app_user_pool_client" {
  name                         = "user-pool-client-${var.stack_name}"
  user_pool_id                 = aws_cognito_user_pool.app_user_pool.id
  generate_secret              = false
  allowed_oauth_flows         = ["code", "implicit"]
  allowed_oauth_scopes        = ["email", "phone", "openid"]
  allowed_oauth_flows_user_credentials = true
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain       = "custom-${var.stack_name}.auth.${var.region}.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
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

resource "aws_api_gateway_rest_api" "app_api" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.app_api.id
  parent_id   = aws_api_gateway_rest_api.app_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "method_any_item" {
  rest_api_id   = aws_api_gateway_rest_api.app_api.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "ANY"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "CognitoAuthorizer"
  rest_api_id            = aws_api_gateway_rest_api.app_api.id
  authorizer_uri         = "arn:aws:cognito-idp:${var.region}:${data.aws_caller_identity.current.account_id}:userpool/${aws_cognito_user_pool.app_user_pool.id}"
  provider_arns          = [aws_cognito_user_pool.app_user_pool.arn]
  type                   = "COGNITO_USER_POOLS"
  identity_validation_expression = "^Bearer [\\w-]{43}$"
}

resource "aws_api_gateway_deployment" "deployment_production" {
  rest_api_id = aws_api_gateway_rest_api.app_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment_production.id
  rest_api_id   = aws_api_gateway_rest_api.app_api.id
  stage_name    = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "UsagePlan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.app_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAILY"
  }
}

resource "aws_lambda_function" "app_lambda" {
  function_name = "app-lambda-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  role = aws_iam_role.lambda_execution_role.arn
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions   = ["dynamodb:*", "logs:*"]
    resources = [aws_dynamodb_table.todo_table.arn]
  }

  statement {
    actions   = ["cloudwatch:*", "xray:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda-policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_amplify_app" "frontend_app" {
  name                           = "amplify-app-${var.stack_name}"
  repository                     = var.amplify_source_repo
  enable_auto_build              = true
  environment_variables = {
    AWS_REGION = var.region
  }

  build_spec = file("buildspec.yml")
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.frontend_app.id
  branch_name = "main"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.app_user_pool.id
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.deployment_production.invoke_url
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend_app.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.app_lambda.arn
}
