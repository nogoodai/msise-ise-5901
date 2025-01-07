terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources"
  default     = "us-east-1"
}

variable "project_name" {
  description = "The base name for all resources"
  default     = "serverless-web-app"
}

variable "stack_name" {
  description = "The name of the deployment stack"
  default     = "prod"
}

variable "github_repo" {
  description = "The GitHub repository for Amplify source"
  default     = "https://github.com/yourusername/yourrepo"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows             = ["code", "implicit"]
  allowed_oauth_scopes            = ["email", "phone", "openid"]
  generate_secret                 = false
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.project_name}-${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo_table" {
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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api"
  description = "API Gateway for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "main" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id

  method_settings {
    metrics_enabled = true
    logging_level   = "INFO"
    data_trace_enabled = true
    http_method     = "*"
    resource_path   = "/*"
  }

  xray_tracing_enabled = true
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.project_name}-usage-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
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

resource "aws_lambda_function" "todo_crud" {
  function_name = "${var.project_name}-todo-crud"
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
}

resource "aws_iam_role" "api_gateway_logging" {
  name = "${var.project_name}-api-gateway-logging-role"

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

resource "aws_iam_role_policy" "api_gateway_logging_policy" {
  name     = "${var.project_name}-api-gateway-logging-policy"
  role     = aws_iam_role.api_gateway_logging.id
  policy   = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "logs:*"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "amplify_exec" {
  name = "${var.project_name}-amplify-role"

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

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec-role"

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

resource "aws_iam_role_policy" "lambda_policy" {
  name     = "${var.project_name}-lambda-policy"
  role     = aws_iam_role.lambda_exec.id
  policy   = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "dynamodb:*",
        "logs:*"
      ]
      Resource = [
        aws_dynamodb_table.todo_table.arn,
        "arn:aws:logs:*:*:*"
      ]
    }]
  })
}

resource "aws_amplify_app" "main" {
  name              = "${var.project_name}-amplify-app"
  repository        = var.github_repo
  iam_service_role  = aws_iam_role.amplify_exec.arn
  
  build_spec = jsonencode({
    version = "1.0"
    build   = {
      commands = [
        "npm install",
        "npm run build",
        "npm run deploy"
      ]
    }
  })
}

resource "aws_amplify_branch" "main" {
  app_id   = aws_amplify_app.main.id
  branch_name = "master"
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
  description = "The URL of the API Gateway"
  value       = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_id" {
  description = "The ID of the Amplify App"
  value       = aws_amplify_app.main.id
}
