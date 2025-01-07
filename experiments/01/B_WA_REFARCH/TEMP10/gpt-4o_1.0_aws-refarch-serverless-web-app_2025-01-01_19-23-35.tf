terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy the infrastructure."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack for resource identification."
  default     = "production-stack"
}

variable "github_source" {
  description = "The GitHub repository for frontend source code."
}

variable "cognito_domain_prefix" {
  description = "Cognito domain prefix for custom domain setup."
  default     = "myapp-${var.stack_name}"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id               = aws_cognito_user_pool.user_pool.id
  name                       = "app-client-${var.stack_name}"
  generate_secret            = false
  allowed_oauth_flows       = ["authorization_code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = var.cognito_domain_prefix
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
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "api-gateway-${var.stack_name}"
  description = "API Gateway for the serverless web application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-app"
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito-authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  identity_source = "method.request.header.Authorization"

  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_lambda_function" "crud_function" {
  for_each = {
    "add-item"      = "POST /item"
    "get-item"      = "GET /item/{id}"
    "get-all-items" = "GET /item"
    "update-item"   = "PUT /item/{id}"
    "complete-item" = "POST /item/{id}/done"
    "delete-item"   = "DELETE /item/{id}"
  }

  function_name = "${each.key}-function-${var.stack_name}"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name               = "lambda_exec_role-${var.stack_name}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  inline_policy {
    name   = "lambda-dynamodb-policy"
    policy = data.aws_iam_policy_document.lambda_dynamodb_policy.json
  }

  inline_policy {
    name   = "lambda-cloudwatch-policy"
    policy = data.aws_iam_policy_document.lambda_cloudwatch_policy.json
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "lambda_dynamodb_policy" {
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem"
    ]
    resources = [aws_dynamodb_table.todo_table.arn]
  }
}

data "aws_iam_policy_document" "lambda_cloudwatch_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  count = length(keys(aws_lambda_function.crud_function))

  name              = "/aws/lambda/${element(values(aws_lambda_function.crud_function), count.index).function_name}"
  retention_in_days = 14
}

resource "aws_amplify_app" "frontend_app" {
  name = "amplify-frontend-${var.stack_name}"
  repository = var.github_source
  oauth_token = "<your-oauth-token>"

  build_spec = <<-EOT
  version: 1
  applications:
    - frontend:
        components:
        - default:
            build:
              commands:
                - npm install
                - npm run build
            artifacts:
              baseDirectory: /build
              files:
                - '**/*'
  EOT
}

resource "aws_amplify_branch" "master_branch" {
  app_id = aws_amplify_app.frontend_app.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name               = "api_gateway_cloudwatch_role-${var.stack_name}"
  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role.json

  inline_policy {
    name   = "api-gateway-cloudwatch-policy"
    policy = data.aws_iam_policy_document.api_gateway_cloudwatch_policy.json
  }
}

data "aws_iam_policy_document" "api_gateway_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["apigateway.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "api_gateway_cloudwatch_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "amplify_role" {
  name               = "amplify_role-${var.stack_name}"
  assume_role_policy = data.aws_iam_policy_document.amplify_assume_role.json

  inline_policy {
    name   = "amplify-policy"
    policy = data.aws_iam_policy_document.amplify_policy.json
  }
}

data "aws_iam_policy_document" "amplify_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["amplify.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "amplify_policy" {
  statement {
    actions = ["*"]
    resources = ["*"]
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "lambda_function_arns" {
  value = { for name, lambda in aws_lambda_function.crud_function : name => lambda.arn }
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend_app.app_id
}
