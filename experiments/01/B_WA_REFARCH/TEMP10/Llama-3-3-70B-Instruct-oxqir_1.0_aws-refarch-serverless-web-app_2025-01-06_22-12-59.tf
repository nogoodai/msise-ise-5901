provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "application_name" {
  default = "todo-application"
}

variable "environment" {
  default = "prod"
}

variable "stack_name" {
  default = "todo-stack"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.application_name}-${var.environment}-user-pool"
  alias_attributes   = ["email"]
  email_verification_message = "Please click the link to verify your email address: {####}"
  email_verification_subject = "Verify your email address"
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.application_name}-${var.environment}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers = ["COGNITO"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain               = "${var.application_name}-${var.environment}.auth.us-west-2.amazoncognito.com"
  user_pool_id         = aws_cognito_user_pool.user_pool.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "dynamodb_table" {
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
  server_side_encryption {
    enabled = true
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.application_name}-${var.environment}-api-gateway"
  description = "API Gateway for ${var.application_name} application"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name          = "${var.application_name}-${var.environment}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "put_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "delete_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "add_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-add-item-function"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dynamodb_table.name
    }
  }
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-get-item-function"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dynamodb_table.name
    }
  }
}

resource "aws_lambda_function" "get_all_items_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-get-all-items-function"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dynamodb_table.name
    }
  }
}

resource "aws_lambda_function" "update_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-update-item-function"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dynamodb_table.name
    }
  }
}

resource "aws_lambda_function" "complete_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-complete-item-function"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dynamodb_table.name
    }
  }
}

resource "aws_lambda_function" "delete_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-delete-item-function"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dynamodb_table.name
    }
  }
}

# API Gateway integration with Lambda functions
resource "aws_api_gateway_integration" "add_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:${aws_lambda_function.add_item_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:${aws_lambda_function.get_item_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_all_items_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:${aws_lambda_function.get_all_items_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "update_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:${aws_lambda_function.update_item_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "complete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:${aws_lambda_function.complete_item_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:${aws_lambda_function.delete_item_function.arn}/invocations"
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "amplify_app" {
  name        = "${var.application_name}-${var.environment}-amplify-app"
  description = "Amplify app for ${var.application_name} application"
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

# IAM roles and policies for API Gateway, Amplify, and Lambda functions
resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.application_name}-${var.environment}-api-gateway-role"
  description = "API Gateway role for ${var.application_name} application"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "api_gateway_role_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsReadOnlyAccess"
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.application_name}-${var.environment}-amplify-role"
  description = "Amplify role for ${var.application_name} application"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "amplify.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "amplify_role_policy" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmplifyReadOnlyAccess"
}

resource "aws_iam_role" "lambda_role" {
  name        = "${var.application_name}-${var.environment}-lambda-role"
  description = "Lambda role for ${var.application_name} application"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_role_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaExecute"
}

resource "aws_iam_policy" "dynamodb_read_policy" {
  name        = "${var.application_name}-${var.environment}-dynamodb-read-policy"
  description = "DynamoDB read policy for ${var.application_name} application"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": "${aws_dynamodb_table.dynamodb_table.arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "dynamodb_write_policy" {
  name        = "${var.application_name}-${var.environment}-dynamodb-write-policy"
  description = "DynamoDB write policy for ${var.application_name} application"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "${aws_dynamodb_table.dynamodb_table.arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_read_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb_read_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_write_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb_write_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.dynamodb_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.add_item_function.function_name,
    aws_lambda_function.get_item_function.function_name,
    aws_lambda_function.get_all_items_function.function_name,
    aws_lambda_function.update_item_function.function_name,
    aws_lambda_function.complete_item_function.function_name,
    aws_lambda_function.delete_item_function.function_name
  ]
}
