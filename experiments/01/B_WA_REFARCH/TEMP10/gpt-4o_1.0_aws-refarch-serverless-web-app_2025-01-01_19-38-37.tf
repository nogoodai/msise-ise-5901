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
  description = "Name of the application stack"
  default     = "web-stack"
}

variable "environment" {
  description = "Environment for the resources"
  default     = "production"
}

locals {
  tags = {
    Name        = "${var.stack_name}-${var.environment}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool" "main" {
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

  tags = local.tags
}

resource "aws_cognito_user_pool_client" "main" {
  name                        = "${var.stack_name}-app-client"
  user_pool_id                = aws_cognito_user_pool.main.id
  explicit_auth_flows         = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows         = ["code", "implicit"]
  allowed_oauth_scopes        = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  generate_secret = false

  tags = local.tags
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name             = "todo-table-${var.stack_name}"
  billing_mode     = "PROVISIONED"
  read_capacity    = 5
  write_capacity   = 5
  
  hash_key         = "cognito-username"
  range_key        = "id"

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

  tags = local.tags
}

resource "aws_api_gateway_rest_api" "service" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = local.tags
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${var.stack_name}-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.service.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  
  environment {
    variables = {
      DYNAMODB_TABLE    = aws_dynamodb_table.main.name
    }
  }
  
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec.arn

  tags = local.tags
}

# Similar Lambda function resources should be defined for other operations such as 'get_item', 'update_item', etc.

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.tags
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name   = "${var.stack_name}-lambda-dynamodb-access"
  role   = aws_iam_role.lambda_exec.id

  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    actions   = ["dynamodb:*"]
    resources = [aws_dynamodb_table.main.arn]
  }
}

resource "aws_amplify_app" "main" {
  name              = "${var.stack_name}-amplify"
  repository        = var.github_repository
  oauth_token       = var.github_oauth_token

  environment_variables = {
    ENV_NAME = "production"
  }

  auto_build = true

  tags = local.tags
}

resource "aws_iam_role" "api_gateway" {
  name = "${var.stack_name}-api-gateway"

  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role.json

  tags = local.tags
}

data "aws_iam_policy_document" "api_gateway_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "api_gateway_logging" {
  role   = aws_iam_role.api_gateway.id

  policy = data.aws_iam_policy_document.api_gateway_logging.json
}

data "aws_iam_policy_document" "api_gateway_logging" {
  statement {
    actions = ["logs:*"]

    resources = ["*"]
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.service.execution_arn
}

output "amplify_app_url" {
  value = aws_amplify_app.main.default_domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "lambda_function_arn" {
  value = aws_lambda_function.add_item.arn
}
