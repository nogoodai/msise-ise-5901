# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region = "us-west-2"
}

# Create a random string for the stack name
resource "random_string" "stack_name" {
  length = 8
  special = false
  upper = false
}

# Create a Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name = "todo-pool-${random_string.stack_name.result}"
  alias_attributes = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }
  tags = {
    Name        = "todo-pool-${random_string.stack_name.result}"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Create a Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name         = "todo-client-${random_string.stack_name.result}"
  user_pool_id = aws_cognito_user_pool.this.id
  generate_secret = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Create a Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "todo-domain-${random_string.stack_name.result}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# Create a DynamoDB table
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${random_string.stack_name.result}"
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
    Name        = "todo-table-${random_string.stack_name.result}"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Create an API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "todo-api-${random_string.stack_name.result}"
  description = "Todo API"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Create an API Gateway authorizer
resource "aws_api_gateway_authorizer" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  name        = "todo-authorizer-${random_string.stack_name.result}"
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

# Create an API Gateway resource
resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

# Create an API Gateway method
resource "aws_api_gateway_method" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

# Create an API Gateway deployment
resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_method.this]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# Create an API Gateway usage plan
resource "aws_api_gateway_usage_plan" "this" {
  name        = "todo-usage-plan-${random_string.stack_name.result}"
  description = "Todo usage plan"
  api_keys = []
}

# Create an API Gateway usage plan key
resource "aws_api_gateway_usage_plan_key" "this" {
  usage_plan_id = aws_api_gateway_usage_plan.this.id
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
}

# Create an API Gateway API key
resource "aws_api_gateway_api_key" "this" {
  name        = "todo-api-key-${random_string.stack_name.result}"
  description = "Todo API key"
}

# Create a Lambda function
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-add-item-${random_string.stack_name.result}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

# Create a Lambda function
resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-get-item-${random_string.stack_name.result}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

# Create a Lambda function
resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-get-all-items-${random_string.stack_name.result}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

# Create a Lambda function
resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-update-item-${random_string.stack_name.result}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

# Create a Lambda function
resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-complete-item-${random_string.stack_name.result}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

# Create a Lambda function
resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-delete-item-${random_string.stack_name.result}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
}

# Create an IAM role for Lambda execution
resource "aws_iam_role" "lambda_exec" {
  name        = "todo-lambda-exec-${random_string.stack_name.result}"
  description = "Todo Lambda execution role"
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

# Create an IAM policy for Lambda execution
resource "aws_iam_policy" "lambda_exec" {
  name        = "todo-lambda-exec-policy-${random_string.stack_name.result}"
  description = "Todo Lambda execution policy"
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
        Resource = aws_dynamodb_table.this.arn
        Effect    = "Allow"
      }
    ]
  })
}

# Attach the IAM policy to the Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

# Create an IAM role for API Gateway execution
resource "aws_iam_role" "api_gateway_exec" {
  name        = "todo-api-gateway-exec-${random_string.stack_name.result}"
  description = "Todo API Gateway execution role"
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

# Create an IAM policy for API Gateway execution
resource "aws_iam_policy" "api_gateway_exec" {
  name        = "todo-api-gateway-exec-policy-${random_string.stack_name.result}"
  description = "Todo API Gateway execution policy"
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
}

# Attach the IAM policy to the API Gateway execution role
resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

# Create an Amplify app
resource "aws_amplify_app" "this" {
  name        = "todo-app-${random_string.stack_name.result}"
  description = "Todo app"
  build_spec  = file("buildspec.yml")
}

# Create an Amplify branch
resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
  stage       = "PROD"
}

# Output the Cognito User Pool ID
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

# Output the Cognito User Pool Client ID
output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

# Output the DynamoDB table ARN
output "dynamodb_table_arn" {
  value = aws_dynamodb_table.this.arn
}

# Output the API Gateway ID
output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

# Output the Lambda function ARNs
output "lambda_function_arns" {
  value = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn
  ]
}

# Output the Amplify app ID
output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
