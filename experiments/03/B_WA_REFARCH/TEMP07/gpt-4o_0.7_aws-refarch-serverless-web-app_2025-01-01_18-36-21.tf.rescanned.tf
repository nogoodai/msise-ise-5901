terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Application stack name"
  type        = string
  default     = "my-serverless-app"
}

resource "aws_cognito_user_pool" "auth" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"

  tags = {
    Name = "user-pool-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "auth_client" {
  name         = "client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.auth.id

  explicit_auth_flows = ["ALLOW_AUTH_CODE_FLOW", "ALLOW_IMPLICIT_FLOW"]

  oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "auth_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.auth.id
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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "todo-table-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_apigatewayv2_api" "gateway" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  }

  tags = {
    Name = "api-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.gateway.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_access_logs.arn
    format          = "$context.requestId $context.identity.sourceIp $context.identity.userAgent $context.requestTime $context.httpMethod $context.resourcePath $context.status"
  }

  tags = {
    Name = "api-stage-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_access_logs" {
  name = "/aws/http-api/${aws_apigatewayv2_api.gateway.id}/access-logs"

  tags = {
    Name = "api-gateway-access-logs-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_auth" {
  api_id       = aws_apigatewayv2_api.gateway.id
  name         = "cognito-authorizer"
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.auth_client.id]
    issuer   = aws_cognito_user_pool.auth.endpoint
  }
}

resource "aws_lambda_function" "crud_functions" {
  for_each = {
    "add_item"    = "POST /item"
    "get_item"    = "GET /item/{id}"
    "get_all"     = "GET /item"
    "update_item" = "PUT /item/{id}"
    "complete"    = "POST /item/{id}/done"
    "delete"      = "DELETE /item/{id}"
  }

  function_name = "${each.key}-function-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec.arn

  tags = {
    Name = "${each.key}-function-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_amplify_app" "frontend" {
  name = "amplify-app-${var.stack_name}"

  repository = "https://github.com/user/repo"

  build_spec = <<EOF
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
      - node_modules/**/*
EOF

  tags = {
    Name = "amplify-app-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

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

  tags = {
    Name = "api-gateway-role-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "api-gateway-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_role.id

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

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "amplify-role-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "amplify-policy-${var.stack_name}"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "amplify:*"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role-${var.stack_name}"

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

  tags = {
    Name = "lambda-exec-role-${var.stack_name}"
    Environment = "production"
    Project = var.stack_name
  }
}

resource "aws_iam_role_policy" "lambda_exec_policy" {
  name = "lambda-exec-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:*",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_accessanalyzer_analyzer" "example" {
  analyzer_name = "example-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name = "example-analyzer"
    Environment = "production"
    Project = var.stack_name
  }
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.auth.id
  description = "The ID of the Cognito User Pool"
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_api.gateway.api_endpoint
  description = "The URL of the API Gateway"
}

output "lambda_function_arns" {
  value       = [for func in aws_lambda_function.crud_functions : func.arn]
  description = "The ARNs of the Lambda functions"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "amplify_app_id" {
  value       = aws_amplify_app.frontend.id
  description = "The ID of the Amplify app"
}
