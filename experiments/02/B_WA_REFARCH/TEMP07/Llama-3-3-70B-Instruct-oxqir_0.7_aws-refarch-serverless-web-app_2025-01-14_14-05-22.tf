terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/todo-frontend"
  description = "The URL of the GitHub repository"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The name of the GitHub branch"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_pool" {
  name                = "${var.application_name}-user-pool"
  email_configuration = {
    email_sending_account = "COGNITO_DEFAULT"
  }
  alias_attributes     = ["email"]
  username_attributes   = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  auto_verified_attributes = ["email"]
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_client" {
  name                = "${var.application_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_pool.id
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-user-pool-client"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "todo_domain" {
  domain       = "${var.application_name}.${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_pool.id
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-user-pool-domain"
    Environment = "prod"
    Project     = var.application_name
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  key_schema = [
    {
      attribute_name = "cognito-username"
      key_type       = "HASH"
    },
    {
      attribute_name = "id"
      key_type       = "RANGE"
    }
  ]
  server_side_encryption {
    enabled = true
  }
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-api"
  description = "Todo API"
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-api"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name          = "todo-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_pool.arn]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_method" "todo_get_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_method" "todo_post_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_integration" "todo_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_get_lambda.arn}/invocations"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_integration" "todo_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_post_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_post_lambda.arn}/invocations"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_integration.todo_get_integration, aws_api_gateway_integration.todo_post_integration]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name = "todo-usage-plan"
  description = "Todo API usage plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
  }
  quota {
    limit  = 5000
    offset = 0
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Functions
resource "aws_lambda_function" "todo_get_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-get-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
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
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-get-lambda"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "todo_post_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-post-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
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
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-post-lambda"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = var.application_name
  description = "Todo App"
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = var.application_name
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_amplify_backend_environment" "todo_environment" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "prod"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_amplify_app_version" "todo_version" {
  app_id      = aws_amplify_app.todo_app.id
  source_code = {
    code_commit = {
      repository_name = "todo-frontend"
      branch_name     = var.github_branch
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "todo_api_gateway_role" {
  name        = "${var.application_name}-api-gateway-role"
  description = "API Gateway role for logging to CloudWatch"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-api-gateway-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "todo_api_gateway_policy" {
  name        = "${var.application_name}-api-gateway-policy"
  description = "API Gateway policy for logging to CloudWatch"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-api-gateway-policy"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_api_gateway_attachment" {
  role       = aws_iam_role.todo_api_gateway_role.name
  policy_arn = aws_iam_policy.todo_api_gateway_policy.arn
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "todo_amplify_role" {
  name        = "${var.application_name}-amplify-role"
  description = "Amplify role for managing Amplify resources"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-amplify-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "todo_amplify_policy" {
  name        = "${var.application_name}-amplify-policy"
  description = "Amplify policy for managing Amplify resources"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:CreateApp",
          "amplify:UpdateApp",
          "amplify:DeleteApp",
        ]
        Effect = "Allow"
        Resource = "arn:aws:amplify:*:*:*"
      }
    ]
  })
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-amplify-policy"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_amplify_attachment" {
  role       = aws_iam_role.todo_amplify_role.name
  policy_arn = aws_iam_policy.todo_amplify_policy.arn
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "todo_lambda_role" {
  name        = "${var.application_name}-lambda-role"
  description = "Lambda role for interacting with DynamoDB and publishing metrics to CloudWatch"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-lambda-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "todo_lambda_policy" {
  name        = "${var.application_name}-lambda-policy"
  description = "Lambda policy for interacting with DynamoDB and publishing metrics to CloudWatch"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name        = "${var.application_name}-lambda-policy"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_lambda_attachment" {
  role       = aws_iam_role.todo_lambda_role.name
  policy_arn = aws_iam_policy.todo_lambda_policy.arn
  lifecycle {
    create_before_destroy = true
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_client.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.todo_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.todo_deployment.stage_name
}

output "lambda_function_name_get" {
  value = aws_lambda_function.todo_get_lambda.function_name
}

output "lambda_function_name_post" {
  value = aws_lambda_function.todo_post_lambda.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.todo_branch.branch_name
}
