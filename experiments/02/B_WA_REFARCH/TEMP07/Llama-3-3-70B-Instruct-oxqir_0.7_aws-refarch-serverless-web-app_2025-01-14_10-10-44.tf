terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-west-2"
}

# Variables
variable "project_name" {
  default = "todo-app"
}

variable "stack_name" {
  default = "prod"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/todo-app"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app" {
  name                = "${var.project_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.project_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls       = ["https://todo-app.com/callback"]
  logout_urls         = ["https://todo-app.com/logout"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain               = "${var.project_name}-${var.stack_name}"
  user_pool_id         = aws_cognito_user_pool.todo_app.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_app" {
  name           = "todo-table-${var.stack_name}"
  read_capacity_units  = 5
  write_capacity_units = 5
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
  server_side_encryption {
    enabled = true
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_app" {
  name        = "${var.project_name}-api"
  description = "REST API for Todo App"
}

resource "aws_api_gateway_authorizer" "todo_app" {
  name        = "${var.project_name}-authorizer"
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app.arn]
}

resource "aws_api_gateway_resource" "todo_app_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  parent_id   = aws_api_gateway_rest_api.todo_app.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_resource" "todo_app_item_id" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  parent_id   = aws_api_gateway_resource.todo_app_item.id
  path_part   = "{id}"
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

resource "aws_api_gateway_method" "todo_app_item_id_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item_id.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_item_id_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item_id.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_item_id_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item_id.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_deployment" "todo_app" {
  depends_on = [
    aws_api_gateway_method.todo_app_item_get,
    aws_api_gateway_method.todo_app_item_post,
    aws_api_gateway_method.todo_app_item_id_get,
    aws_api_gateway_method.todo_app_item_id_put,
    aws_api_gateway_method.todo_app_item_id_delete,
  ]
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  stage_name  = var.stack_name
}

resource "aws_api_gateway_usage_plan" "todo_app" {
  name        = "${var.project_name}-usage-plan"
  description = "Usage plan for Todo App"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_app.id
    stage  = aws_api_gateway_deployment.todo_app.stage_name
  }

  quota {
    limit  = 5000
    offset = 100
    period = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
resource "aws_lambda_function" "todo_app_add_item" {
  filename      = "lambda-functions/add-item.zip"
  function_name = "${var.project_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "todo_app_get_item" {
  filename      = "lambda-functions/get-item.zip"
  function_name = "${var.project_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "todo_app_get_all_items" {
  filename      = "lambda-functions/get-all-items.zip"
  function_name = "${var.project_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "todo_app_update_item" {
  filename      = "lambda-functions/update-item.zip"
  function_name = "${var.project_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "todo_app_complete_item" {
  filename      = "lambda-functions/complete-item.zip"
  function_name = "${var.project_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "todo_app_delete_item" {
  filename      = "lambda-functions/delete-item.zip"
  function_name = "${var.project_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

# API Gateway Integration
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

resource "aws_api_gateway_integration" "todo_app_item_id_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item_id.id
  http_method = aws_api_gateway_method.todo_app_item_id_get.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_item_id_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item_id.id
  http_method = aws_api_gateway_method.todo_app_item_id_put.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_item_id_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app_item_id.id
  http_method = aws_api_gateway_method.todo_app_item_id_delete.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_delete_item.arn}/invocations"
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.project_name}-app"
  description = "Amplify app for Todo App"
  platform    = "WEB"
}

resource "aws_amplify_branch" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_backend_environment" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "prod"
}

resource "aws_amplify_domain_association" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  domain_name = "${var.project_name}.com"
}

# IAM Roles and Policies
resource "aws_iam_role" "todo_app_api_gateway" {
  name        = "${var.project_name}-api-gateway"
  description = "API Gateway role for Todo App"

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

resource "aws_iam_policy" "todo_app_api_gateway" {
  name        = "${var.project_name}-api-gateway-policy"
  description = "API Gateway policy for Todo App"

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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_app_api_gateway" {
  role       = aws_iam_role.todo_app_api_gateway.name
  policy_arn = aws_iam_policy.todo_app_api_gateway.arn
}

resource "aws_iam_role" "todo_app_amplify" {
  name        = "${var.project_name}-amplify"
  description = "Amplify role for Todo App"

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

resource "aws_iam_policy" "todo_app_amplify" {
  name        = "${var.project_name}-amplify-policy"
  description = "Amplify policy for Todo App"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:UpdateApp",
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_app_amplify" {
  role       = aws_iam_role.todo_app_amplify.name
  policy_arn = aws_iam_policy.todo_app_amplify.arn
}

resource "aws_iam_role" "todo_app_lambda" {
  name        = "${var.project_name}-lambda"
  description = "Lambda role for Todo App"

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

resource "aws_iam_policy" "todo_app_lambda" {
  name        = "${var.project_name}-lambda-policy"
  description = "Lambda policy for Todo App"

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
        Resource = aws_dynamodb_table.todo_app.arn
        Effect    = "Allow"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_app_lambda" {
  role       = aws_iam_role.todo_app_lambda.name
  policy_arn = aws_iam_policy.todo_app_lambda.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_app.id
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.todo_app_add_item.arn,
    aws_lambda_function.todo_app_get_item.arn,
    aws_lambda_function.todo_app_get_all_items.arn,
    aws_lambda_function.todo_app_update_item.arn,
    aws_lambda_function.todo_app_complete_item.arn,
    aws_lambda_function.todo_app_delete_item.arn,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.todo_app.branch_name
}
