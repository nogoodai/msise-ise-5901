terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application stack"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "The GitHub token for Amplify"
}

variable "github_repo" {
  type        = string
  description = "The GitHub repository for the frontend application"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch for the frontend application"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes    = ["email"]
  auto_verified_attributes = ["email"]
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain               = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id         = aws_cognito_user_pool.todo_app.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_app" {
  name        = "${var.stack_name}-api"
  description = "API for the Todo application"
}

resource "aws_api_gateway_resource" "todo_app_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  parent_id   = aws_api_gateway_rest_api.todo_app.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_app_item_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_item_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_item_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_item_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_authorizer" "todo_app" {
  name          = "${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app.arn]
  rest_api_id   = aws_api_gateway_rest_api.todo_app.id
}

resource "aws_api_gateway_stage" "todo_app" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.todo_app.id
  deployment_id = aws_api_gateway_deployment.todo_app.id
}

resource "aws_api_gateway_deployment" "todo_app" {
  depends_on = [
    aws_api_gateway_method.todo_app_item_get,
    aws_api_gateway_method.todo_app_item_post,
    aws_api_gateway_method.todo_app_item_put,
    aws_api_gateway_method.todo_app_item_delete,
  ]
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
}

resource "aws_api_gateway_usage_plan" "todo_app" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for the Todo application"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_app.id
    stage  = aws_api_gateway_stage.todo_app.stage_name
  }
  quota {
    limit  = 5000
    offset = 0
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit   = 50
  }
}

# Lambda Functions
resource "aws_lambda_function" "todo_app_add_item" {
  filename      = "lambda_functions/add_item.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_get_item" {
  filename      = "lambda_functions/get_item.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_get_all_items" {
  filename      = "lambda_functions/get_all_items.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_update_item" {
  filename      = "lambda_functions/update_item.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_complete_item" {
  filename      = "lambda_functions/complete_item.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_delete_item" {
  filename      = "lambda_functions/delete_item.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

# API Gateway Lambda Integration
resource "aws_api_gateway_integration" "todo_app_item_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item.id
  http_method = aws_api_gateway_method.todo_app_item_get.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_item_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item.id
  http_method = aws_api_gateway_method.todo_app_item_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_item_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item.id
  http_method = aws_api_gateway_method.todo_app_item_put.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_item_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item.id
  http_method = aws_api_gateway_method.todo_app_item_delete.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_delete_item.arn}/invocations"
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-app"
  description = "Amplify app for the Todo application"
  platform   = "WEB"
}

resource "aws_amplify_branch" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "prod"
}

resource "aws_amplify_backend_environment" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  environment = aws_amplify_environment.todo_app.environment
}

resource "aws_amplify_backend" "todo_app" {
  app_id = aws_amplify_app.todo_app.id
}

resource "aws_amplify_backend_api" "todo_app" {
  app_id = aws_amplify_app.todo_app.id
  api_id = aws_amplify_backend.todo_app.api_id
}

# IAM Roles and Policies
resource "aws_iam_role" "todo_app_api_gateway" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "API Gateway role for the Todo application"

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

resource "aws_iam_policy" "todo_app_api_gateway" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "API Gateway policy for the Todo application"

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
}

resource "aws_iam_role_policy_attachment" "todo_app_api_gateway" {
  role       = aws_iam_role.todo_app_api_gateway.name
  policy_arn = aws_iam_policy.todo_app_api_gateway.arn
}

resource "aws_iam_role" "todo_app_lambda" {
  name        = "${var.stack_name}-lambda-role"
  description = "Lambda role for the Todo application"

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

resource "aws_iam_policy" "todo_app_lambda" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Lambda policy for the Todo application"

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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_app_lambda" {
  role       = aws_iam_role.todo_app_lambda.name
  policy_arn = aws_iam_policy.todo_app_lambda.arn
}

resource "aws_iam_role" "todo_app_amplify" {
  name        = "${var.stack_name}-amplify-role"
  description = "Amplify role for the Todo application"

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

resource "aws_iam_policy" "todo_app_amplify" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Amplify policy for the Todo application"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateBackendEnvironment",
          "amplify:CreateBackend",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_app_amplify" {
  role       = aws_iam_role.todo_app_amplify.name
  policy_arn = aws_iam_policy.todo_app_amplify.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_app.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_stage.todo_app.stage_name
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.todo_app.branch_name
}
