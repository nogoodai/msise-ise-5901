provider "aws" {
  region = "us-west-2"
}

variable "application_name" {
  type        = string
  default     = "todo-app"
}

variable "stack_name" {
  type        = string
  default     = "prod"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/your-repo/todo-app"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Cognito User Pool

resource "aws_cognito_user_pool" "user_pool" {
  name                     = "${var.application_name}-${var.stack_name}-user-pool"
  email_verification_subject = "Your verification code"
  email_verification_message = "Please verify your email address. {####} is your verification code."
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  alias_attributes         = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.user_pool.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/callback"]
  logout_urls                           = ["http://localhost:3000/logout"]
  supported_identity_providers         = ["COGNITO"]
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito Custom Domain

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain       = "${var.application_name}-${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table

resource "aws_dynamodb_table" "todo_table" {
  name           = "${var.application_name}-${var.stack_name}-todo-table"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-todo-table"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API for ${var.application_name}"
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item_function.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.application_name}-${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.get_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = var.stack_name
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name         = "${var.application_name}-${var.stack_name}-usage-plan"
  description  = "Usage plan for ${var.application_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }
  quota {
    limit  = 5000
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions

resource "aws_lambda_function" "add_item_function" {
  filename      = "add_item_function.zip"
  function_name = "${var.application_name}-${var.stack_name}-add-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-add-item-function"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "get_item_function.zip"
  function_name = "${var.application_name}-${var.stack_name}-get-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-get-item-function"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_all_items_function" {
  filename      = "get_all_items_function.zip"
  function_name = "${var.application_name}-${var.stack_name}-get-all-items-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-get-all-items-function"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "update_item_function" {
  filename      = "update_item_function.zip"
  function_name = "${var.application_name}-${var.stack_name}-update-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-update-item-function"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "complete_item_function" {
  filename      = "complete_item_function.zip"
  function_name = "${var.application_name}-${var.stack_name}-complete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-complete-item-function"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item_function" {
  filename      = "delete_item_function.zip"
  function_name = "${var.application_name}-${var.stack_name}-delete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-delete-item-function"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify App

resource "aws_amplify_app" "app" {
  name        = "${var.application_name}-${var.stack_name}-app"
  description = "Amplify app for ${var.application_name}"
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "environment" {
  app_id      = aws_amplify_app.app.id
  branch_name = aws_amplify_branch.branch.branch_name
  environment_name = var.stack_name
}

# IAM Roles and Policies

resource "aws_iam_role" "lambda_role" {
  name        = "${var.application_name}-${var.stack_name}-lambda-role"
  description = "Lambda role for ${var.application_name}"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.application_name}-${var.stack_name}-lambda-policy"
  description = "Lambda policy for ${var.application_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-role"
  description = "API Gateway role for ${var.application_name}"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
  description = "API Gateway policy for ${var.application_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.application_name}-${var.stack_name}-amplify-role"
  description = "Amplify role for ${var.application_name}"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.application_name}-${var.stack_name}-amplify-policy"
  description = "Amplify policy for ${var.application_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateEnvironment",
          "amplify:DeleteApp",
          "amplify:DeleteBranch",
          "amplify:DeleteEnvironment",
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetEnvironment"
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Outputs

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "api_gateway_deployment_id" {
  value = aws_api_gateway_deployment.deployment.id
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.add_item_function.arn,
    aws_lambda_function.get_item_function.arn,
    aws_lambda_function.get_all_items_function.arn,
    aws_lambda_function.update_item_function.arn,
    aws_lambda_function.complete_item_function.arn,
    aws_lambda_function.delete_item_function.arn
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.branch.branch_name
}
