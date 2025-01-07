terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for resource naming"
  default     = "my-app"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify app"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                     = "${var.stack_name}-client"
  user_pool_id             = aws_cognito_user_pool.main.id
  generate_secret          = false
  allowed_oauth_flows      = ["code", "implicit"]
  allowed_oauth_scopes     = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "main" {
  domain                    = "${var.stack_name}-auth"
  user_pool_id              = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo" {
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

resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.stack_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "cloudwatch:PutMetricData",
    ]
    resources = [aws_dynamodb_table.todo.arn]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "crud_functions" {
  function_name    = "${var.stack_name}-crud"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  publish          = true
  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")

  tracing_config {
    mode = "Active"
  }
}

resource "aws_apigateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = <<EOF
{
  "swagger": "2.0",
  "info": {
    "title": "My API",
    "version": "1.0"
  },
  "paths": {
    "/item": {
      "get": {
        "x-amazon-apigateway-integration": {
          "uri": "${aws_lambda_function.crud_functions.invoke_arn}",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      }
    }
  }
}
EOF
}

resource "aws_apigateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_apigateway_rest_api.api.id
  deployment_id = aws_apigateway_deployment.api.id

  variables = {
    lambdaAliasVar = "live"
  }
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format          = "$context.ip $context.requestId $context.extendedRequestId $context.status"
  }
}

resource "aws_apigateway_usage_plan" "plan" {
  name = "${var.stack_name}-usage-plan"
  
  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_iot_account_auditing_configuration" "iot_audit" {
  account_id = "123456789012"

  audit_notification_target {
    target_arn = arn
    role_arn   = arn
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  role   = aws_iam_role.api_gateway_role.id
  policy = data.aws_iam_policy_document.api_gateway_policy.json
}

data "aws_iam_policy_document" "api_gateway_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/apigateway/*"]
  }
}

resource "aws_amplify_app" "frontend_app" {
  name          = "${var.stack_name}-frontend"
  repository    = var.github_repo
  oauth_token   = data.aws_secretsmanager_secret_version.github_token.secret_string

  build_spec = <<EOT
version: 1.0
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
      - '**/*'
EOT

  custom_rule {
    source    = "</^[^.]+$|\\.(?!(css|js|html|png)$)([^.]+$)/>"
    target    = "/index.html"
    status    = "200"
  }
}

resource "aws_amplify_branch" "master" {
  app_id                  = aws_amplify_app.frontend_app.id
  branch_name             = "master"
  enable_auto_build       = true
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name = "/aws/apigateway/${aws_apigateway_rest_api.api.name}"
  retention_in_days = 14
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = "github-token"
}

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "api_url" {
  description = "API Gateway Invoke URL"
  value       = aws_apigateway_stage.prod.invoke_url
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.todo.arn
}
