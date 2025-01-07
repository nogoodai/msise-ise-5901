provider "aws" {
  region = "us-east-1"
  version = "5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
}

variable "project_name" {
  type        = string
  default     = "todo-project"
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
}

variable "github_repo_owner" {
  type        = string
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.project_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  name                = "${var.project_name}-user-pool-client"
  user_pool_id      = aws_cognito_user_pool.user_pool.id
  generate_secret   = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "domain" {
  domain               = "${var.stack_name}-${var.environment}"
  user_pool_id         = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "table" {
  name                = "todo-table-${var.stack_name}"
  billing_mode       = "PROVISIONED"
  read_capacity_units = 5
  write_capacity_units = 5
  hash_key           = "cognito-username"
  range_key          = "id"

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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-api"
  description = "API for Todo App"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = var.environment
}

resource "aws_api_gateway_stage" "stage" {
  stage_name    = var.environment
  rest_api_id = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.project_name}-usage-plan"
  description = "Usage Plan for Todo App"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.stage.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Cognito User Pool Authorizer
resource "aws_api_gateway_authorizer" "authorizer" {
  name          = "${var.project_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# Lambda Function
resource "aws_lambda_function" "add_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.project_name}-add-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "get_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.project_name}-get-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.project_name}-get-all-items"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "update_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.project_name}-update-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "complete_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.project_name}-complete-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "delete_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.project_name}-delete-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_role.arn
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
}

# API Gateway Integration
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_integration" "item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${aws_lambda_function.add_item.function_name}/invocations"
}

resource "aws_api_gateway_method" "item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_authorizer" "item_authorizer" {
  name          = "${var.project_name}-item-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# Amplify App
resource "aws_amplify_app" "app" {
  name        = "${var.project_name}-app"
  description = "Amplify App for Todo Project"
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = "master"
}

resource "aws_amplify_environment" "env" {
  app_id      = aws_amplify_app.app.id
  environment_name = var.environment
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_role" {
  name        = "${var.project_name}-lambda-role"
  description = "IAM Role for Lambda Functions"

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
  name        = "${var.project_name}-lambda-policy"
  description = "IAM Policy for Lambda Functions"

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
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.table.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.project_name}-api-gateway-role"
  description = "IAM Role for API Gateway"

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
  name        = "${var.project_name}-api-gateway-policy"
  description = "IAM Policy for API Gateway"

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
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.table.name
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${aws_region}.amazonaws.com/${var.environment}/item"
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.branch.branch_name
}
