terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "stack_name" {
  default = "my-stack"
}

variable "application_name" {
  default = "my-application"
}

variable "github_repository" {
  description = "GitHub repository for Amplify"
}

resource "aws_cognito_user_pool" "auth" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  user_pool_id = aws_cognito_user_pool.auth.id
  domain       = "${var.application_name}-${var.stack_name}"
}

resource "aws_cognito_user_pool_client" "auth_client" {
  user_pool_id                   = aws_cognito_user_pool.auth.id
  generate_secret                = false
  allowed_oauth_flows           = ["authorization_code", "implicit"]
  allowed_oauth_scopes          = ["email", "phone", "openid"]
}

resource "aws_dynamodb_table" "todos" {
  name           = "todo-table-${var.stack_name}"
  hash_key       = "cognito-username"
  range_key      = "id"
  billing_mode   = "PROVISIONED"
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

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-role"

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

resource "aws_iam_policy" "api_gateway_logging_policy" {
  name   = "${var.application_name}-${var.stack_name}-api-gateway-logging-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_logging" {
  policy_arn = aws_iam_policy.api_gateway_logging_policy.arn
  role       = aws_iam_role.api_gateway_role.name
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api"
  description = "API Gateway for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  provider = aws
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_cognito_user_pool_authorizer.auth.id
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_cognito_user_pool_authorizer.auth.id
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.application_name}-${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec.arn

  # Assume that the code is packaged properly and that the relevant S3 bucket and key are known
  s3_bucket = "<code-bucket>"
  s3_key    = "<lambda-code-key>"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.application_name}-${var.stack_name}-lambda-exec"

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
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.application_name}-${var.stack_name}-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.todos.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "xray:PutTraceSegments"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  policy_arn = aws_iam_policy.lambda_policy.arn
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_amplify_app" "frontend" {
  name             = "${var.application_name}-${var.stack_name}-frontend"
  repository       = var.github_repository
  oauth_token      = "<github-token>" # sensitive information should be handled with caution
  enable_auto_build = true

  build_spec = <<EOF
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

  custom_rule {
    source = "</>"
    target = "/index.html"
    status = "200"
  }
}

resource "aws_apigateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api.id
  xray_tracing_enabled = true
}

resource "aws_apigateway_usage_plan" "usage_plan" {
  name = "UsagePlan"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_apigateway_stage.prod.id
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

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.auth.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todos.name
}

output "api_gateway_url" {
  value = "${aws_api_gateway_rest_api.api.execution_arn}/prod"
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
