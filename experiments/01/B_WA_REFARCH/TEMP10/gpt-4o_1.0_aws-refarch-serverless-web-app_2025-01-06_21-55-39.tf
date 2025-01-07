terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to create resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name to associate with AWS resources."
  default     = "prod"
}

variable "github_repo" {
  description = "GitHub repository for the Amplify app."
  type        = string
}

variable "cognito_domain_prefix" {
  description = "Custom domain prefix for Cognito."
  default     = "app-prod"
}

resource "aws_cognito_user_pool" "main" {
  name = "user-pool-${var.stack_name}"

  schema {
    name     = "email"
    attribute_data_type = "String"
    required = true
    username_attribute = true
  }

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "cognito-user-pool-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id          = aws_cognito_user_pool.main.id
  generate_secret       = false
  callback_urls         = ["https://example.com/callback"]
  allowed_oauth_flows   = ["code", "implicit"]
  allowed_oauth_scopes  = ["email", "openid", "phone"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "cognito-client-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "cognito-domain-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_dynamodb_table" "main" {
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

  tags = {
    Name        = "dynamodb-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "api-gateway-${var.stack_name}"
  description = "API Gateway for serverless web app"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id

  xray_tracing_enabled = true

  tags = {
    Name        = "api-gateway-stage-prod"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
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
    Name        = "api-usage-plan-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "crud_operations" {
  function_name = "${var.stack_name}-lambda-function"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.main.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "lambda-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role-${var.stack_name}"

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

  tags = {
    Name        = "iam-role-lambda-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_amplify_app" "main" {
  name          = "amplify-app-${var.stack_name}"
  repository    = var.github_repo
  oauth_token   = var.oauth_token

  environment_variables = {
    _LIVEUPDATE = true
  }

  # This is a placeholder and would typically reference a valid build specification
  build_spec = file("amplify-buildspec.yml")

  auto_branch_creation {
    enable_auto_build = true
    patterns          = ["*"]
  }

  auto_branch_creation_config {
    basic_auth_credentials = "user:pass"
    password_protection    = false
  }

  tags = {
    Name        = "amplify-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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

  tags = {
    Name        = "iam-role-apigateway-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_policy" "api_gateway_cloudwatch_logging" {
  name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_role_attach" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_logging.arn
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  description = "DynamoDB Table Name"
  value       = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_api_gateway_rest_api.main.id
}

output "lambda_function_name" {
  description = "Lambda Function Name"
  value       = aws_lambda_function.crud_operations.function_name
}

output "amplify_app_id" {
  description = "Amplify App ID"
  value       = aws_amplify_app.main.id
}
