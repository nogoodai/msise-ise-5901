terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy this solution in."
  type        = string
  default     = "us-west-2"
}

variable "stack_name" {
  description = "The name of the stack to use for AWS resources."
  type        = string
  default     = "my-app-stack"
}

variable "cognito_custom_domain" {
  description = "The custom domain name for the Cognito user pool."
  type        = string
  default     = "auth.my-app.com"
}

resource "aws_cognito_user_pool" "main" {
  name = "user-pool-${var.stack_name}"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain = var.cognito_custom_domain
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows = ["code", "implicit"]

  allowed_oauth_scopes = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  hash_key = "cognito-username"
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

resource "aws_api_gateway_rest_api" "main" {
  name        = "api-gateway-${var.stack_name}"
  description = "API Gateway for the ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  provider {
    logging_level = "INFO"
    metrics_enabled = true
  }

  api_key_source = "HEADER"
}

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"

  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id
}

resource "aws_api_gateway_authorizer" "cognito_auth" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"
  deployment_id = aws_api_gateway_deployment.prod.id

  access_log_settings {
    destination_arn = "${aws_cloudwatch_log_group.api_gateway_logs.arn}"
    format          = "$context.requestId - $context.identity.sourceIp - $context.protocol - $context.requestTime - $context.httpMethod - $context.resourcePath - $context.status - $context.responseLength"
  }

  metrics_enabled = true
}

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-function"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/api-gateway/${aws_api_gateway_rest_api.main.name}"
  retention_in_days = 14
}

resource "aws_iam_role" "lambda_exec" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_policy" {
  name = "lambda_policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem"
      ],
      "Effect": "Allow",
      "Resource": "${aws_dynamodb_table.todo_table.arn}"
    },
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_amplify_app" "frontend" {
  name  = "amplify-app-${var.stack_name}"
  repository = "https://github.com/user/repo"

  build_spec = <<EOF
version: 0.1
backend:
  phases:
    build:
      commands:
        - amplifyPush --simple
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
artifacts:
  baseDirectory: build
EOF

  auto_branch_creation_patterns = ["master"]
}

resource "aws_iam_role" "amplify_role" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "amplify.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSAmplifyAdminAccess"
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "The base URL of the API Gateway"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_id" {
  description = "The ID of the Amplify App"
  value       = aws_amplify_app.frontend.id
}
