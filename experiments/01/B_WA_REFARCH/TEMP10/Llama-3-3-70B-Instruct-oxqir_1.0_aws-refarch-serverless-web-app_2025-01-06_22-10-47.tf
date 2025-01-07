provider "aws" {
  region = "us-east-1"
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "application_name" {
  default = "todo-app"
}

variable "stack_name" {
  default = "main-stack"
}

variable "github_repository" {
  default = "https://github.com/user/todo-app.git"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_pool" {
  name = "todo-user-pool-${var.stack_name}"
  alias_attributes = ["email"]
  email_verification_message = "Your verification code is {####}."
  sms_verification_message = "Your verification code is {####}."
  email_configuration {
    source_arn = aws_ses_email_identity.todo_identity.arn
    reply_to_email_address = "noreply@${var.application_name}.com"
    email_sending_account = "DEVELOPER"
  }
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers = false
    require_symbols = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_client" {
  name = "todo-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_pool.id
  generate_secret = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

# Custom Domain for Cognito
resource "aws_cognito_user_pool_domain" "todo_domain" {
  domain = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
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

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for todo application"
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_get_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_post_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_put_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_delete_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_integration" "todo_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_post_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_put_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_put_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_delete_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_delete_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item_lambda.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name           = "todo-authorizer-${var.stack_name}"
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_pool.arn]
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_integration.todo_get_integration, aws_api_gateway_integration.todo_post_integration, aws_api_gateway_integration.todo_put_integration, aws_api_gateway_integration.todo_delete_integration]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

# Lambda Functions
resource "aws_lambda_function" "add_item_lambda" {
  filename      = "lambda-functions/add-item-lambda.zip"
  function_name = "add-item-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.add_item_lambda_role.arn
}

resource "aws_lambda_function" "get_item_lambda" {
  filename      = "lambda-functions/get-item-lambda.zip"
  function_name = "get-item-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.get_item_lambda_role.arn
}

resource "aws_lambda_function" "update_item_lambda" {
  filename      = "lambda-functions/update-item-lambda.zip"
  function_name = "update-item-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.update_item_lambda_role.arn
}

resource "aws_lambda_function" "delete_item_lambda" {
  filename      = "lambda-functions/delete-item-lambda.zip"
  function_name = "delete-item-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.delete_item_lambda_role.arn
}

resource "aws_lambda_permission" "add_item_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_item_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "update_item_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_item_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "delete_item_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_item_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

# IAM Roles and Policies
resource "aws_iam_role" "add_item_lambda_role" {
  name        = "add-item-lambda-role-${var.stack_name}"
  description = "IAM role for add item lambda"
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

resource "aws_iam_role" "get_item_lambda_role" {
  name        = "get-item-lambda-role-${var.stack_name}"
  description = "IAM role for get item lambda"
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

resource "aws_iam_role" "update_item_lambda_role" {
  name        = "update-item-lambda-role-${var.stack_name}"
  description = "IAM role for update item lambda"
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

resource "aws_iam_role" "delete_item_lambda_role" {
  name        = "delete-item-lambda-role-${var.stack_name}"
  description = "IAM role for delete item lambda"
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

resource "aws_iam_role_policy" "add_item_lambda_policy" {
  name   = "add-item-lambda-policy-${var.stack_name}"
  role   = aws_iam_role.add_item_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
}

resource "aws_iam_role_policy" "get_item_lambda_policy" {
  name   = "get-item-lambda-policy-${var.stack_name}"
  role   = aws_iam_role.get_item_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy" "update_item_lambda_policy" {
  name   = "update-item-lambda-policy-${var.stack_name}"
  role   = aws_iam_role.update_item_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
}

resource "aws_iam_role_policy" "delete_item_lambda_policy" {
  name   = "delete-item-lambda-policy-${var.stack_name}"
  role   = aws_iam_role.delete_item_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.application_name}-${var.stack_name}"
  description = "Amplify app for todo application"
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "main"
}

resource "aws_amplify_environment" "todo_environment" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "prod"
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "lambda_function_name" {
  value = aws_lambda_function.add_item_lambda.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}
