provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
}

variable "project_name" {
  type        = string
  default     = "my-project"
}

variable "environment" {
  type        = string
  default     = "prod"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/my-repo/my-repo.git"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

variable "cognito_email" {
  type        = string
  default     = "my-email@example.com"
}

variable "cognito_callback_urls" {
  type        = list(string)
  default     = ["https://example.com/callback"]
}

variable "cognito_allowed_o_auth_flows" {
  type        = list(string)
  default     = ["authorization_code", "implicit"]
}

variable "cognito_allowed_o_auth_scopes" {
  type        = list(string)
  default     = ["email", "phone", "openid"]
}

variable "dynamodb_table_read_capacity_units" {
  type        = number
  default     = 5
}

variable "dynamodb_table_write_capacity_units" {
  type        = number
  default     = 5
}

variable "api_gateway_daily_request_limit" {
  type        = number
  default     = 5000
}

variable "api_gateway_burst_limit" {
  type        = number
  default     = 100
}

variable "api_gateway_rate_limit" {
  type        = number
  default     = 50
}

variable "lambda_runtime" {
  type        = string
  default     = "nodejs14.x"
}

variable "lambda_memory_size" {
  type        = number
  default     = 1024
}

variable "lambda_timeout" {
  type        = number
  default     = 60
}

resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes    = ["email"]
  email_verification_message = "Your verification code is {####}. "
  email_verification_subject = "Your verification code"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_o_auth_flows = var.cognito_allowed_o_auth_flows
  allowed_o_auth_scopes = var.cognito_allowed_o_auth_scopes
  callback_urls       = var.cognito_callback_urls
  logout_urls         = ["https://example.com/logout"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain               = "${var.stack_name}-auth"
  user_pool_id         = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = var.dynamodb_table_read_capacity_units
  write_capacity_units = var.dynamodb_table_write_capacity_units
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
  timeouts {
    create = "1h"
    delete = "1h"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name           = "${var.stack_name}-cognito-authorizer"
  rest_api_id    = aws_api_gateway_rest_api.api.id
  type           = "COGNITO_USER_POOLS"
  provider_arns  = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_provider.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item_lambda.arn}/invocations"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [aws_api_gateway_integration.get_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = var.environment
}

resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name         = "${var.stack_name}-usage-plan"
  description  = "Usage plan for ${var.stack_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
  }
  quota {
    limit  = var.api_gateway_daily_request_limit
    offset = 0
    period = "DAY"
  }
  throttle {
    burst_limit = var.api_gateway_burst_limit
    rate_limit  = var.api_gateway_rate_limit
  }
}

resource "aws_lambda_function" "get_item_lambda" {
  filename      = "get-item-lambda.zip"
  function_name = "${var.stack_name}-get-item-lambda"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout
}

resource "aws_lambda_function" "add_item_lambda" {
  filename      = "add-item-lambda.zip"
  function_name = "${var.stack_name}-add-item-lambda"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout
}

resource "aws_lambda_function" "update_item_lambda" {
  filename      = "update-item-lambda.zip"
  function_name = "${var.stack_name}-update-item-lambda"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout
}

resource "aws_lambda_function" "delete_item_lambda" {
  filename      = "delete-item-lambda.zip"
  function_name = "${var.stack_name}-delete-item-lambda"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout
}

resource "aws_lambda_function" "complete_item_lambda" {
  filename      = "complete-item-lambda.zip"
  function_name = "${var.stack_name}-complete-item-lambda"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout
}

resource "aws_amplify_app" "app" {
  name        = "${var.stack_name}-app"
  description = "Amplify app for ${var.stack_name}"
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = var.github_branch
}

resource "aws_iam_role" "api_gateway_exec_role" {
  name        = "${var.stack_name}-api-gateway-exec-role"
  description = "API Gateway execution role for ${var.stack_name}"

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
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "API Gateway policy for ${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_attach" {
  role       = aws_iam_role.api_gateway_exec_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_exec_role" {
  name        = "${var.stack_name}-amplify-exec-role"
  description = "Amplify execution role for ${var.stack_name}"

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
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Amplify policy for ${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_attach" {
  role       = aws_iam_role.amplify_exec_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.stack_name}-lambda-exec-role"
  description = "Lambda execution role for ${var.stack_name}"

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
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Lambda policy for ${var.stack_name}"

  policy = jsonencode({
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.api_deployment.stage_name
}

output "lambda_function_name" {
  value = aws_lambda_function.get_item_lambda.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.branch.branch_name
}
