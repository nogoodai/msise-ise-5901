# Configure the AWS Provider
terraform {
  required_version = ">= 0.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "example" {
  name                    = var.stack_name
  username_attributes     = ["email"]
  auto_verify_email       = true
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  lifecycle {
    prevent_destroy = false
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "example" {
  name                         = "example-client"
  user_pool_id                 = aws_cognito_user_pool.example.id
  generate_secret              = false
  supported_identity_providers = []
  allowed_oauth_flows          = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes        = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "example" {
  domain       = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.example.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "example" {
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
  lifecycle {
    prevent_destroy = false
  }
  server_side_encryption {
    enabled = true
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "example" {
  name        = "${var.stack_name}-api"
  description = "Example API"
}

resource "aws_api_gateway_authorizer" "example" {
  name          = "example-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.example.arn]
}

resource "aws_api_gateway_resource" "example" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_rest_api.example.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "example_get" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.example.id
}

resource "aws_api_gateway_method" "example_post" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.example.id
}

resource "aws_api_gateway_method" "example_put" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.example.id
}

resource "aws_api_gateway_method" "example_delete" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.example.id
}

resource "aws_api_gateway_integration" "example_get" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example_get.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.stack_name}-lambda/invocations"
}

resource "aws_api_gateway_integration" "example_post" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.stack_name}-lambda/invocations"
}

resource "aws_api_gateway_integration" "example_put" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example_put.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.stack_name}-lambda/invocations"
}

resource "aws_api_gateway_integration" "example_delete" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example_delete.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.stack_name}-lambda/invocations"
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "example" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.example.arn
}

resource "aws_iam_role" "example" {
  name        = "${var.stack_name}-lambda-execution-role"
  description = "Execution role for lambda function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "example" {
  name        = "${var.stack_name}-lambda-execution-policy"
  description = "Execution policy for lambda function"

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
        Resource = aws_dynamodb_table.example.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "example" {
  role       = aws_iam_role.example.name
  policy_arn = aws_iam_policy.example.arn
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "example" {
  name        = var.stack_name
  description = "Example Amplify App"
}

resource "aws_amplify_branch" "example" {
  app_id      = aws_amplify_app.example.id
  branch_name = "master"
}

resource "aws_amplify.Environment" "example" {
  app_id      = aws_amplify_app.example.id
  environment = "prod"
}

# IAM roles and policies for API Gateway to log to CloudWatch
resource "aws_iam_role" "api_gateway" {
  name        = "${var.stack_name}-api-gateway-execution-role"
  description = "Execution role for API Gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "api_gateway" {
  name        = "${var.stack_name}-api-gateway-execution-policy"
  description = "Execution policy for API Gateway"

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
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

# IAM roles and policies for Amplify to manage resources
resource "aws_iam_role" "amplify" {
  name        = "${var.stack_name}-amplify-execution-role"
  description = "Execution role for Amplify"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "amplify" {
  name        = "${var.stack_name}-amplify-execution-policy"
  description = "Execution policy for Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

variable "stack_name" {
  type        = string
  default     = "example"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.example.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.example.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.example.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.example.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.example.id
}
