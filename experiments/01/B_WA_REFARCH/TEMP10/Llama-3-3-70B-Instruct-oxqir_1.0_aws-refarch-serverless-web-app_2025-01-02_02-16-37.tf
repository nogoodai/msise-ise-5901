provider "aws" {
  region = "us-east-1"
  version = "5.1.0"
}

variable "project_name" {
  type        = string
  default     = "todo-app"
}

variable "environment" {
  type        = string
  default     = "prod"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/your-username/todo-app"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

variable "aws_account_id" {
  type        = string
}

variable "cloudwatch_log_group_name" {
  type        = string
  default     = "/aws/apigateway/todo-api"
}

variable "cloudwatch_log_group_retention" {
  type        = number
  default     = 30
}

variable "api_gateway_rest_api_name" {
  type        = string
  default     = "todo-api"
}

variable "api_gateway_stage_name" {
  type        = string
  default     = "prod"
}

variable "lambda_function_runtime" {
  type        = string
  default     = "nodejs12.x"
}

variable "lambda_function_memory_size" {
  type        = number
  default     = 1024
}

variable "lambda_function_timeout" {
  type        = number
  default     = 60
}

# Cognito User Pool

resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.project_name}-${var.environment}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  EmailVerificationMessage = "Your verification code is {####}. "
  EmailVerificationSubject = "Your verification code"
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client

resource "aws_cognito_user_pool_client" "client" {
  name                = "${var.project_name}-${var.environment}-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain

resource "aws_cognito_user_pool_domain" "domain" {
  domain               = "${var.project_name}-${var.environment}"
  user_pool_id         = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table

resource "aws_dynamodb_table" "table" {
  name                = "${var.project_name}-${var.environment}-todo-table"
  read_capacity_units = 5
  write_capacity_units = 5
  hash_key             = "cognito-username"
  range_key            = "id"

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
}

# API Gateway

resource "aws_api_gateway_rest_api" "api" {
  name        = var.api_gateway_rest_api_name
  description = "TODO API"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name        = "cognito-authorizer"
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "item"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.get_item_integration, aws_api_gateway_integration.post_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = var.api_gateway_stage_name
}

# Lambda Functions

resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.environment}-add-item"
  handler       = "index.handler"
  runtime       = var.lambda_function_runtime
  role          = aws_iam_role.lambda_exec.arn
  timeout       = var.lambda_function_timeout
  memory_size   = var.lambda_function_memory_size
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.table.name
    }
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.environment}-get-item"
  handler       = "index.getHandler"
  runtime       = var.lambda_function_runtime
  role          = aws_iam_role.lambda_exec.arn
  timeout       = var.lambda_function_timeout
  memory_size   = var.lambda_function_memory_size
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.table.name
    }
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.environment}-update-item"
  handler       = "index.updateHandler"
  runtime       = var.lambda_function_runtime
  role          = aws_iam_role.lambda_exec.arn
  timeout       = var.lambda_function_timeout
  memory_size   = var.lambda_function_memory_size
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.table.name
    }
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.environment}-delete-item"
  handler       = "index.deleteHandler"
  runtime       = var.lambda_function_runtime
  role          = aws_iam_role.lambda_exec.arn
  timeout       = var.lambda_function_timeout
  memory_size   = var.lambda_function_memory_size
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.table.name
    }
  }
}

resource "aws_lambda_permission" "get_item_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "post_item_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# Amplify

resource "aws_amplify_app" "app" {
  name        = var.project_name
  description = "TODO App"
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = var.github_branch
}

resource "aws_amplify_backend_environment" "env" {
  app_id      = aws_amplify_app.app.id
  environment = var.environment
}

# IAM Roles and Policies

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.project_name}-${var.environment}-lambda-exec"
  description = " Execution role for Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-${var.environment}-lambda-policy"
  description = "Policy for Lambda execution"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.table.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.project_name}-${var.environment}-api-gateway-exec"
  description = "Execution role for API Gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.project_name}-${var.environment}-api-gateway-policy"
  description = "Policy for API Gateway execution"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.project_name}-${var.environment}-amplify-exec"
  description = "Execution role for Amplify"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.project_name}-${var.environment}-amplify-policy"
  description = "Policy for Amplify execution"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateBackendEnvironment",
        ]
        Resource = "*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.table.name
}

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.deployment.stage_name
}

output "lambda_function_name" {
  value = aws_lambda_function.add_item.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.branch.branch_name
}
