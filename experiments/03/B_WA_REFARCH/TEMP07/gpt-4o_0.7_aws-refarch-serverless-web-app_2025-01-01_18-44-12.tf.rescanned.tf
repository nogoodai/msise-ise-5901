terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  description = "The AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "stack_name" {
  type        = string
  description = "The stack name to identify resources"
  default     = "prod-stack"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository URL for Amplify"
}

resource "aws_cognito_user_pool" "app_user_pool" {
  name = "user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
  }

  mfa_configuration = "OPTIONAL"

  tags = {
    Name = "user-pool-${var.stack_name}"
    Environment = "production"
    Project = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "app_user_pool_client" {
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
  generate_secret = true
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "app_domain" {
  domain = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key    = "cognito-username"
  range_key   = "id"

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
    Project = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for managing to-do items"
  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Name = "todo-api-${var.stack_name}"
    Environment = "production"
    Project = "serverless-web-app"
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format          = "$context.identity.sourceIp - $context.identity.caller [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
  }

  client_certificate_id = aws_api_gateway_client_certificate.client_cert.id

  tags = {
    Name = "api-stage-${var.stack_name}"
    Environment = "production"
    Project = "serverless-web-app"
  }
}

resource "aws_api_gateway_client_certificate" "client_cert" {
  description = "Client certificate for API Gateway"
}

resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name = "/aws/api-gateway/todo-api-${var.stack_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name = "add-item-${var.stack_name}"
    Environment = "production"
    Project = "serverless-web-app"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json

  tags = {
    Name = "lambda-exec-role-${var.stack_name}"
    Environment = "production"
    Project = "serverless-web-app"
  }
}

data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec_role.id
  policy = data.aws_iam_policy_document.lambda_dynamodb_policy.json
}

data "aws_iam_policy_document" "lambda_dynamodb_policy" {
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:DeleteItem",
      "cloudwatch:PutMetricData"
    ]
    resources = [aws_dynamodb_table.todo_table.arn]
  }
}

resource "aws_amplify_app" "frontend" {
  name = "amplify-app-${var.stack_name}"
  repository = var.github_repo

  build_spec = jsonencode({
    version = "1.0"
    frontend = {
      phases = {
        preBuild = {
          commands = ["npm install"]
        }
        build = {
          commands = ["npm run build"]
        }
      }
      artifacts = {
        baseDirectory = "/build"
        files = ["**/*"]
      }
      cache = {
        paths = ["node_modules/**/*"]
      }
    }
  })

  tags = {
    Name = "amplify-app-${var.stack_name}"
    Environment = "production"
    Project = "serverless-web-app"
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id = aws_amplify_app.frontend.id
  branch_name = "master"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.app_user_pool.id
  description = "The ID of the Cognito User Pool"
}

output "api_gateway_url" {
  value       = aws_api_gateway_stage.api_stage.invoke_url
  description = "The URL of the API Gateway"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "amplify_app_id" {
  value       = aws_amplify_app.frontend.id
  description = "The ID of the Amplify App"
}
