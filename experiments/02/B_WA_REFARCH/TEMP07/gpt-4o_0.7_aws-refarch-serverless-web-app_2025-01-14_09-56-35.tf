terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for resource naming"
  type        = string
  default     = "my-app"
}

variable "github_repo" {
  description = "The GitHub repository for Amplify app"
  type        = string
}

resource "aws_cognito_user_pool" "auth" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "app" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.auth.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret     = false
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls       = ["https://${aws_cognito_user_pool_domain.auth.domain}/oauth2/idpresponse"]
}

resource "aws_cognito_user_pool_domain" "auth" {
  domain      = "${var.stack_name}-auth-domain"
  user_pool_id = aws_cognito_user_pool.auth.id
}

resource "aws_dynamodb_table" "todo" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

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

  provisioned_throughput {
    read_capacity  = 5
    write_capacity = 5
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.prod.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format          = "$context.identity.sourceIp - $context.identity.caller [$context.requestTime] \"$context.httpMethod $context.resourcePath\" $context.status $context.responseLength $context.requestId"
  }

  xray_tracing_enabled = true
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.stack_name}-api"
  retention_in_days = 90
}

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = "${timestamp()}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "api" {
  name = "${var.stack_name}-usage-plan"
  
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
    period = "DAY"
  }
}

resource "aws_lambda_function" "crud" {
  function_name = "${var.stack_name}-crud-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo.name
    }
  }

  source_code_hash = filebase64sha256("lambda.zip")
  filename         = "lambda.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.dynamodb_crud.arn
}

resource "aws_iam_policy" "dynamodb_crud" {
  name        = "${var.stack_name}-dynamodb-crud"
  description = "Policy to allow DynamoDB CRUD operations"
  policy      = file("dynamodb-crud-policy.json")
}

resource "aws_amplify_app" "frontend" {
  name  = "${var.stack_name}-frontend"
  repository = var.github_repo

  build_spec = <<EOF
version: 1
applications:
  - frontend:
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
}

resource "aws_amplify_branch" "master_branch" {
  app_id              = aws_amplify_app.frontend.id
  branch_name         = "master"
  enable_auto_build   = true
}

resource "aws_iam_role" "api_gateway_exec" {
  name = "${var.stack_name}-api-gateway-exec-role"

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

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify_exec" {
  name = "${var.stack_name}-amplify-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAmplifyAdminAccess"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.auth.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.prod.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
