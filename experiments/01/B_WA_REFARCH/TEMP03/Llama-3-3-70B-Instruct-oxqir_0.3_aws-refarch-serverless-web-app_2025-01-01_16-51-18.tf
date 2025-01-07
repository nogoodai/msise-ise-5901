provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "The GitHub token for Amplify"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/todo-app.git"
  description = "The GitHub repository for Amplify"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch for Amplify"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  email_configuration {
    email_sending_account = "DEVELOPER"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain               = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id         = aws_cognito_user_pool.todo_app.id
}

# DynamoDB table
resource "aws_dynamodb_table" "todo_table" {
  name           = "${var.stack_name}-todo-table"
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
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_app" {
  name        = "${var.stack_name}-api"
  description = "The API for the todo app"
}

resource "aws_api_gateway_resource" "todo_app" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  parent_id   = aws_api_gateway_rest_api.todo_app.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_app_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
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

resource "aws_api_gateway_deployment" "todo_app" {
  depends_on = [aws_api_gateway_method.todo_app_get, aws_api_gateway_method.todo_app_post, aws_api_gateway_method.todo_app_put, aws_api_gateway_method.todo_app_delete]
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_app" {
  name        = "${var.stack_name}-usage-plan"
  description = "The usage plan for the todo app"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_app.id
    stage  = aws_api_gateway_deployment.todo_app.stage_name
  }

  quota {
    limit  = 5000
    offset = 2
    period  = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda functions
resource "aws_lambda_function" "todo_app_add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_app_get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_app_get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_app_update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_app_complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_app_delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "todo_app_add_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_app_add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_get_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_app_get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_app_get_all_items.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_update_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_app_update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_complete_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_app_complete_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_delete_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.todo_app_delete_item.arn}/invocations"
}

# Amplify app
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-app"
  description = "The Amplify app for the todo app"
}

resource "aws_amplify_branch" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "prod"
}

# IAM roles and policies
resource "aws_iam_role" "todo_app_api_gateway" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "The IAM role for the API Gateway"

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
  name        = "${var.stack_name}-api-gateway-policy"
  description = "The IAM policy for the API Gateway"

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
  name        = "${var.stack_name}-amplify-role"
  description = "The IAM role for the Amplify"

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
  name        = "${var.stack_name}-amplify-policy"
  description = "The IAM policy for the Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateEnvironment",
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
  name        = "${var.stack_name}-lambda-role"
  description = "The IAM role for the Lambda"

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
  name        = "${var.stack_name}-lambda-policy"
  description = "The IAM policy for the Lambda"

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
        Resource = aws_dynamodb_table.todo_table.arn
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

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_app.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.todo_app.stage_name
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
