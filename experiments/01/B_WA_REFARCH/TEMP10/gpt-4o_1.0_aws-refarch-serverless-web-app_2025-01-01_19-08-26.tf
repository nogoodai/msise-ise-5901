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
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack for unique resource naming"
  default     = "my-stack"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  default     = "user/repo"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  policies {
    password_policy {
      minimum_length    = 6
      require_lowercase = true
      require_uppercase = true
      require_numbers   = false
      require_symbols   = false
    }
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-${var.application_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name        = "${var.stack_name}-user-pool-domain"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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

  tags = {
    Name        = "${var.stack_name}-todo-table"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.stack_name}-prod-stage"
    Environment = "production"
    Project     = "serverless-webapp"
  }
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

  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_lambda_function" "lambda" {
  count = length(var.lambda_functions)

  function_name = "${var.stack_name}-${element(var.lambda_functions, count.index)}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  code {
    s3_bucket = var.lambda_code_bucket
    s3_key    = "${var.lambda_code_key_prefix}/${element(var.lambda_functions, count.index)}.zip"
  }

  environment {
    variables = {
      DYNAMO_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  iam_role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "${var.stack_name}-${element(var.lambda_functions, count.index)}"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.stack_name}-amplify-app"

  repository = "https://github.com/${var.github_repo}"

  build_spec = <<EOT
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - yarn install
    build:
      commands:
        - yarn run build
  artifacts:
    # IMPORTANT - Please verify your build output directory
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOT

  auto_branch_creation_config {
    enable_auto_build = true
  }

  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id     = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name        = "${var.stack_name}-master-branch"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json

  tags = {
    Name        = "${var.stack_name}-lambda-exec"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
}

resource "aws_iam_role" "apigateway_role" {
  name = "${var.stack_name}-apigateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.stack_name}-apigateway-role"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_iam_policy" "apigateway-cloudwatch-logs" {
  name        = "${var.stack_name}-apigateway-cloudwatch-logs"

  policy = data.aws_iam_policy_document.apigateway_cloudwatch.json

  tags = {
    Name        = "${var.stack_name}-apigateway-cloudwatch-policy"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_iam_role_policy_attachment" "attach_apigateway_cloudwatch_logs" {
  role       = aws_iam_role.apigateway_role.name
  policy_arn = aws_iam_policy.apigateway-cloudwatch-logs.arn
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"

  policy = data.aws_iam_policy_document.amplify_policy.json

  tags = {
    Name        = "${var.stack_name}-amplify-policy"
    Environment = "production"
    Project     = "serverless-webapp"
  }
}

resource "aws_iam_role_policy_attachment" "attach_amplify_policy" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "apigateway_cloudwatch" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }
}

data "aws_iam_policy_document" "amplify_policy" {
  statement {
    effect = "Allow"

    actions = [
      "amplify:*",
      "s3:*",
      "cloudfront:*"
    ]

    resources = ["*"]
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
