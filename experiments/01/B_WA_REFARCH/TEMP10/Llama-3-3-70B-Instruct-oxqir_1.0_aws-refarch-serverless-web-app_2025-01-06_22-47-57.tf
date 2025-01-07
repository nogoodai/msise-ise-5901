# Configure the AWS Provider
terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.2.5"
}

provider "aws" {
  region = "us-west-2"
}

# Variables for configuration
variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/my-repo"
  description = "The GitHub repository URL for Amplify"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch for Amplify"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "this" {
  name                = "${var.stack_name}-user-pool"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
  password_policy {
    minimum_length                   = 6
    require_lowercase                = true
    require_uppercase               = true
    require_numbers                  = false
    require_symbols                  = false
  }
  username_configuration {
    case_sensitive = false
  }
  alias_attributes = ["email"]
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_o_auth_flows = [
    "authorization_code",
    "implicit"
  ]
  allowed_o_auth_flows_user_pool_client = true
  allowed_o_auth_scopes = [
    "email",
    "phone",
    "openid"
  ]
  callback_urls = [
    "http://localhost:3000/callback"
  ]
  logout_urls = [
    "http://localhost:3000/logout"
  ]
  supported_identity_providers = [
    "COGNITO"
  ]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "this" {
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
  table_status = "ACTIVE"
  server_side_encryption {
    enabled = true
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"
}

resource "aws_api_gateway_authorizer" "this" {
  name          = "${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "this_post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "this_get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "this_put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "this_delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_stage" "this" {
  stage_name    = "prod"
  rest_api_id = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_integration.this_post,
    aws_api_gateway_integration.this_get,
    aws_api_gateway_integration.this_put,
    aws_api_gateway_integration.this_delete
  ]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }
  quota {
    limit  = 5000
    offset = 2
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "this_add" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.this_add.arn
}

resource "aws_lambda_function" "this_get" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.this_get.arn
}

resource "aws_lambda_function" "this_put" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.this_put.arn
}

resource "aws_lambda_function" "this_delete" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.this_delete.arn
}

resource "aws_api_gateway_integration" "this_post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.this_add.arn}/invocations"
}

resource "aws_api_gateway_integration" "this_get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.this_get.arn}/invocations"
}

resource "aws_api_gateway_integration" "this_put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this_put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.this_put.arn}/invocations"
}

resource "aws_api_gateway_integration" "this_delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this_delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.this_delete.arn}/invocations"
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "this" {
  name        = var.stack_name
  description = "Amplify app for ${var.stack_name}"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment = "prod"
}

# IAM roles and policies for API Gateway, Lambda, and Amplify
resource "aws_iam_role" "this_api_gateway" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "Role for API Gateway"

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

resource "aws_iam_policy" "this_api_gateway" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "Policy for API Gateway"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "this_api_gateway" {
  role       = aws_iam_role.this_api_gateway.name
  policy_arn = aws_iam_policy.this_api_gateway.arn
}

resource "aws_iam_role" "this_add" {
  name        = "${var.stack_name}-add-item-role"
  description = "Role for add item Lambda function"

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

resource "aws_iam_role" "this_get" {
  name        = "${var.stack_name}-get-item-role"
  description = "Role for get item Lambda function"

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

resource "aws_iam_role" "this_put" {
  name        = "${var.stack_name}-update-item-role"
  description = "Role for update item Lambda function"

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

resource "aws_iam_role" "this_delete" {
  name        = "${var.stack_name}-delete-item-role"
  description = "Role for delete item Lambda function"

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

resource "aws_iam_policy" "this_lambda" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for Lambda functions"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "this_add" {
  role       = aws_iam_role.this_add.name
  policy_arn = aws_iam_policy.this_lambda.arn
}

resource "aws_iam_role_policy_attachment" "this_get" {
  role       = aws_iam_role.this_get.name
  policy_arn = aws_iam_policy.this_lambda.arn
}

resource "aws_iam_role_policy_attachment" "this_put" {
  role       = aws_iam_role.this_put.name
  policy_arn = aws_iam_policy.this_lambda.arn
}

resource "aws_iam_role_policy_attachment" "this_delete" {
  role       = aws_iam_role.this_delete.name
  policy_arn = aws_iam_policy.this_lambda.arn
}

resource "aws_iam_role" "this_amplify" {
  name        = "${var.stack_name}-amplify-role"
  description = "Role for Amplify"

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

resource "aws_iam_policy" "this_amplify" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Policy for Amplify"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "this_amplify" {
  role       = aws_iam_role.this_amplify.name
  policy_arn = aws_iam_policy.this_amplify.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.this.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.this_add.function_name,
    aws_lambda_function.this_get.function_name,
    aws_lambda_function.this_put.function_name,
    aws_lambda_function.this_delete.function_name
  ]
}
