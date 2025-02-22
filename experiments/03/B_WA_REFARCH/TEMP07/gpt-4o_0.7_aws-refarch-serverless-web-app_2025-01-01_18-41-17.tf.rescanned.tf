terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy the resources in"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack"
  type        = string
  default     = "my-stack"
}

variable "application_name" {
  description = "The name of the application"
  type        = string
  default     = "my-app"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.application_name}-${var.stack_name}-user-pool"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.application_name}-${var.stack_name}-client"

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret     = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API for ${var.application_name}"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_stage_log.arn
    format          = "$context.requestId $context.identity.sourceIp $context.identity.caller $context.identity.user $context.identity.userAgent $context.requestTime $context.httpMethod $context.resourcePath $context.status $context.protocol $context.responseLength"
  }

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-prod-stage"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "api_gw_stage_log" {
  name = "/aws/api_gw/${var.application_name}-${var.stack_name}"

  retention_in_days = 30
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.application_name}-${var.stack_name}-usage-plan"

  api_stages {
    api_id     = aws_api_gateway_rest_api.api.id
    stage      = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    offset = 0
    period = "DAY"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-usage-plan"
    Environment = "production"
    Project     = var.application_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "lambda_function" {
  for_each = {
    "add_item"    = "POST /item"
    "get_item"    = "GET /item/{id}"
    "get_all"     = "GET /item"
    "update_item" = "PUT /item/{id}"
    "complete_item" = "POST /item/{id}/done"
    "delete_item" = "DELETE /item/{id}"
  }

  function_name = "${var.application_name}-${var.stack_name}-${each.key}"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "lambda-${each.key}"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_permission" "api_gateway" {
  for_each = toset(["add_item", "get_item", "get_all", "update_item", "complete_item", "delete_item"])

  statement_id  = "AllowExecutionFromAPIGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function[each.key].arn
  principal     = "apigateway.amazonaws.com"
}

# Amplify
resource "aws_amplify_app" "amplify_app" {
  name               = "${var.application_name}-${var.stack_name}"
  repository         = "https://github.com/user/repo"
  build_spec         = <<EOF
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  environment_variables = {
    "ENV" = "prod"
  }

  iam_service_role_arn = aws_iam_role.amplify_service_role.arn
}

resource "aws_amplify_branch" "master" {
  app_id              = aws_amplify_app.amplify_app.id
  branch_name         = "master"
  enable_auto_build   = true
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-exec"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-exec"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.application_name}-${var.stack_name}-lambda-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan"
      ],
      "Resource": "${aws_dynamodb_table.todo_table.arn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": "xray:PutTraceSegments",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.application_name}-${var.stack_name}-apigateway-cloudwatch-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-apigateway-cloudwatch-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name   = "${var.application_name}-${var.stack_name}-cloudwatch-policy"
  role   = aws_iam_role.api_gateway_cloudwatch_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "amplify_service_role" {
  name = "${var.application_name}-${var.stack_name}-amplify-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "amplify.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name   = "${var.application_name}-${var.stack_name}-amplify-policy"
  role   = aws_iam_role.amplify_service_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "amplify:CreateApp",
        "amplify:CreateBranch",
        "amplify:CreateDeployment",
        "amplify:UpdateApp",
        "amplify:UpdateBranch",
        "amplify:DeleteApp",
        "amplify:DeleteBranch",
        "amplify:StartDeployment"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito User Pool."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_url" {
  value       = aws_api_gateway_stage.prod.invoke_url
  description = "The URL of the API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.amplify_app.id
  description = "The ID of the Amplify App."
}
