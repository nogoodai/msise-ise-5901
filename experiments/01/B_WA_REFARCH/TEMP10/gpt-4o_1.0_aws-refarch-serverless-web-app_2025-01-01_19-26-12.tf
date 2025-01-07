terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy the resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the application stack"
  default     = "myapp"
}

resource "aws_cognito_user_pool" "user_pool" {
  name                = "user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret = false
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
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

  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API for serverless web application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                    = "cognito-authorizer"
  type                    = "COGNITO_USER_POOLS"
  rest_api_id             = aws_api_gateway_rest_api.api.id
  identity_source         = "method.request.header.Authorization"
  provider_arns           = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.default.id
}

resource "aws_api_gateway_deployment" "default" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
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
    limit = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "lambda_func" {
  function_name = "lambda-${each.value}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  dynamic "environment" {
    for_each = keys(local.lambda_env_vars)
    content {
      variables = local.lambda_env_vars[each.key]
    }
  }
  lifecycle {
    ignore_changes = [source_code_hash]
  }
}

locals {
  lambda_env_vars = {
    "add-item" = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    },
    // Add configuration for other lambda functions as needed
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda-function.zip"
}

resource "aws_amplify_app" "amplify_app" {
  name              = "amplify-app-${var.stack_name}"
  repository        = "https://github.com/your-repo/your-project"
  branch            = "master"
  build_spec        = file("${path.module}/amplify-build-spec.yml")

  auto_branch_creation {
    auto_build = true
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_role_${var.stack_name}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  inline_policy {
    name = "DynamoDBAccess"
    policy = data.aws_iam_policy_document.dynamo_policy.json
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "dynamo_policy" {
  statement {
    actions   = ["dynamodb:*"]
    resources = [aws_dynamodb_table.todo_table.arn]
    effect    = "Allow"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api_gateway_role_${var.stack_name}"
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

resource "aws_iam_policy" "api_gateway_logging" {
  name        = "ApiGatewayLoggingPolicy"
  description = "Allow API Gateway to log to CloudWatch"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Effect   = "Allow"
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_api_gateway_logging_policy" {
  policy_arn = aws_iam_policy.api_gateway_logging.arn
  role       = aws_iam_role.api_gateway_role.name
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamo_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_endpoint" {
  description = "The endpoint URL of the API Gateway"
  value       = aws_api_gateway_rest_api.api.execution_arn
}
