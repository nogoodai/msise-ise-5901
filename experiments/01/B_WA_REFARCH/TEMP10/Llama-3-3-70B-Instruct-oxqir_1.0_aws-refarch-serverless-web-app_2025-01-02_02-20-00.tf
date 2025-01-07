# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }

  required_version = ">= 1.2.5"
}

# Provider configuration for AWS
provider "aws" {
  region = "us-east-1"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "pool" {
  name                = "todo-app-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  email_configuration {
    email_sending_account = "DEVELOPER"
  }
  password_policy {
    minimum_length      = 6
    require_uppercase   = true
    require_lowercase   = true
    require_numbers     = false
    require_symbols     = false
  }
  tags = {
    Name        = "Todo App User Pool"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "client" {
  name                = "todo-app-client"
  user_pool_id       = aws_cognito_user_pool.pool.id
  generate_secret    = false
  allowed_oauth_flows        = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes        = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "todo-app.auth.us-east-1.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.pool.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "table" {
  name           = "todo-table-${aws_cognito_user_pool.pool.name}"
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
  tags = {
    Name        = "Todo Table"
    Environment = "production"
    Project     = "todo-app"
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "api" {
  name        = "todo-api"
  description = "API for Todo App"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                             = "CognitoAuthorizer"
  rest_api_id                      = aws_api_gateway_rest_api.api.id
  type                             = "COGNITO_USER_POOLS"
  provider_arns                    = [aws_cognito_user_pool.pool.arn]
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_item.http_method
  type        = "LAMBDA"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.function.arn}/invocations"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.post_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "function" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-lambda-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.table.name
    }
  }
  tags = {
    Name        = "Todo Lambda Function"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name        = "lambda-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-execution-policy"
  description = "Policy for Lambda execution"
  policy      = jsonencode({
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

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "app" {
  name        = "todo-app"
  description = "Amplify App for Todo App"
  platform    = "WEB"
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.app.id
  branch_name = "master"
}

resource "aws_amplify_environment" "production" {
  app_id      = aws_amplify_app.app.id
  branch_name = aws_amplify_branch.master.branch_name
  environment = "production"
}

# IAM roles and policies
resource "aws_iam_role" "api_gateway_role" {
  name        = "api-gateway-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "api-gateway-execution-policy"
  description = "Policy for API Gateway execution"
  policy      = jsonencode({
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

resource "aws_iam_role_policy_attachment" "api_gateway_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "amplify-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "amplify-execution-policy"
  description = "Policy for Amplify execution"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetEnvironment",
        ]
        Resource = "*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "lambda_function_name" {
  value = aws_lambda_function.function.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}
