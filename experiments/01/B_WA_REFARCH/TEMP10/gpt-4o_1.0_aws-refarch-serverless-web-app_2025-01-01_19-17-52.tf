terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, prod)"
  default     = "prod"
}

variable "stack_name" {
  description = "The stack name for resource identification"
  default     = "serverless-app"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify app source"
  default     = "https://github.com/user/repo"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  
  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id      = aws_cognito_user_pool.main.id
  name              = "${var.stack_name}-user-pool-client"
  generate_secret   = false
  supported_identity_providers = ["COGNITO"]
  allowed_oauth_flows          = ["code", "implicit"]
  allowed_oauth_scopes         = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.stack_name}-cognito-domain"
  user_pool_id = aws_cognito_user_pool.main.id
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name = "${var.stack_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = var.environment
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  deployment_id    = aws_api_gateway_deployment.main.id
  rest_api_id      = aws_api_gateway_rest_api.main.id
  stage_name       = "prod"
  cache_cluster_enabled = false
  metrics_enabled       = true
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"

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

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
  
  source_code_hash = filebase64sha256("lambda_functions/add_item.zip")

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_amplify_app" "frontend" {
  name                = "${var.stack_name}-frontend"
  repository          = var.github_repo
  oauth_token         = "github_token" // replace with valid GitHub token
  build_spec          = file("amplify.yml")

  auto_branch_creation_config {
    enable_auto_build = true
    enable_basic_auth = false
  }
  
  tags = {
    Name        = "${var.stack_name}-frontend"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "main" {
  app_id    = aws_amplify_app.frontend.id
  branch_name = "master"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"
  
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name        = "${var.stack_name}-lambda-exec-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name   = "${var.stack_name}-lambda-dynamodb-policy"

  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    actions   = ["dynamodb:*"]
    effect    = "Allow"
    resources = [aws_dynamodb_table.todo.arn]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.main.invoke_url
}

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "amplify_app_url" {
  value = aws_amplify_app.frontend.default_domain
}
