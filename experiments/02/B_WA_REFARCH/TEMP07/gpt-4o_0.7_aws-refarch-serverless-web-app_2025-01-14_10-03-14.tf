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
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name"
  type        = string
  default     = "my-app"
}

variable "environment" {
  description = "The environment for resource tagging"
  type        = string
  default     = "production"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify app"
  type        = string
}

resource "aws_cognito_user_pool" "user_pool" {
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

  tags = {
    Name        = "cognito-user-pool-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "openid", "phone"]
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "cognito-user-pool-client-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain      = "${var.stack_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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

  tags = {
    Name        = "dynamodb-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API for ${var.stack_name} application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  xray_tracing_enabled = true

  tags = {
    Name        = "api-stage-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode({
      resources = aws_lambda_function.lambda_functions[*].function_name
    }))
  }
}

resource "aws_lambda_function" "lambda_functions" {
  count         = 6
  function_name = element(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"], count.index)
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

  tags = {
    Name        = "lambda-${element(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"], count.index)}-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role-${var.stack_name}"

  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json

  tags = {
    Name        = "lambda-execution-role-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
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

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-app-${var.stack_name}"

  repository = var.github_repo
  branch     = "master"

  auto_branch_creation_config {
    patterns = ["master"]
  }

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = data.aws_iam_policy_document.api_gateway_assume_role_policy.json

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

data "aws_iam_policy_document" "api_gateway_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_access" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = data.aws_iam_policy_document.amplify_assume_role_policy.json

  tags = {
    Name        = "amplify-role-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

data "aws_iam_policy_document" "amplify_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["amplify.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "amplify_access" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "API Gateway URL"
  value       = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_url" {
  description = "Amplify App URL"
  value       = aws_amplify_app.amplify_app.default_domain
}
