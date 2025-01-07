terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to create resources in."
  default     = "us-west-2"
}

variable "stack_name" {
  description = "The name of the stack, used in resource naming."
  default     = "myapp"
}

variable "github_repository" {
  description = "The GitHub repository for Amplify"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"
  
  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "client" {
  user_pool_id   = aws_cognito_user_pool.user_pool.id
  name           = "${var.stack_name}-user-pool-client"
  generate_secret = false

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "openid", "phone"]
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain      = "${var.stack_name}.auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name} web application."

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
  variables = {
    lambda_function_arn = var.lambda_function_arn
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on  = [aws_api_gateway_method.method]
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan"

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

resource "aws_lambda_function" "crud_functions" {
  for_each = {
    "addItem"       = "POST /item",
    "getItem"       = "GET /item/{id}",
    "getAllItems"   = "GET /item",
    "updateItem"    = "PUT /item/{id}",
    "completeItem"  = "POST /item/{id}/done",
    "deleteItem"    = "DELETE /item/{id}",
  }

  function_name = "${var.stack_name}-${each.key}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
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

  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "${var.stack_name}-${each.key}-lambda"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.stack_name}-amplify-app"
  repository = var.github_repository

  automatic_branch_creation {
    enable_auto_build = true
  }

  environment_variables = {
    "AMPLIFY_MONOREPO_APP_ROOT" = "/path/to/root"
  }
}

resource "aws_amplify_branch" "master" {
  app_id   = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "dynamodb:*"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      },
      {
        "Action" : [
          "logs:*"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_role_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json
}

data "aws_iam_policy_document" "api_gateway_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"
  
  assume_role_policy = data.aws_iam_policy_document.amplify_assume_role_policy.json
}

data "aws_iam_policy_document" "amplify_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["amplify.amazonaws.com"]
    }

    effect = "Allow"
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
