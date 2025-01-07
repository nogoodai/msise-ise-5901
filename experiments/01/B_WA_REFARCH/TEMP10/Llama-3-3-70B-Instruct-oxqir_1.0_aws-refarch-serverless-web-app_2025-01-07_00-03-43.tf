provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
}

variable "environment" {
  type        = string
  default     = "prod"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "todo_app" {
  name                = "${var.stack_name}-user-pool"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain               = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id         = aws_cognito_user_pool.todo_app.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "todo_app" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "todo_app" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"
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
  stage_name  = var.environment
}

resource "aws_api_gateway_usage_plan" "todo_app" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name}"
}

resource "aws_api_gateway_usage_plan_key" "todo_app" {
  usage_plan_id = aws_api_gateway_usage_plan.todo_app.id
  key_id        = aws_api_gateway_api_key.todo_app.id
  key_type      = "API_KEY"
}

resource "aws_api_gateway_api_key" "todo_app" {
  name        = "${var.stack_name}-api-key"
}

resource "aws_api_gateway_quota" "todo_app" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  quota {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_api_gateway_request_validator" "todo_app" {
  name        = "${var.stack_name}-request-validator"
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  validate_request_body = true
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "todo_app_add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_function" "todo_app_delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda.arn
}

resource "aws_lambda_permission" "todo_app_add_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_app_add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_app.execution_arn}/*/*"
}

resource "aws_lambda_permission" "todo_app_get_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_app_get_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_app.execution_arn}/*/*"
}

resource "aws_lambda_permission" "todo_app_get_all_items" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_app_get_all_items.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_app.execution_arn}/*/*"
}

resource "aws_lambda_permission" "todo_app_update_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_app_update_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_app.execution_arn}/*/*"
}

resource "aws_lambda_permission" "todo_app_complete_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_app_complete_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_app.execution_arn}/*/*"
}

resource "aws_lambda_permission" "todo_app_delete_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_app_delete_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_app.execution_arn}/*/*"
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-app"
  description = "Amplify app for ${var.stack_name}"
}

resource "aws_amplify_branch" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"
}

resource "aws_amplify_environment" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  environment = var.environment
}

# IAM roles and policies for API Gateway to log to CloudWatch
resource "aws_iam_role" "todo_app_api_gateway" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "IAM role for API Gateway"

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
  description = "IAM policy for API Gateway"

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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_app_api_gateway" {
  role       = aws_iam_role.todo_app_api_gateway.name
  policy_arn = aws_iam_policy.todo_app_api_gateway.arn
}

# IAM roles and policies for Amplify to manage resources
resource "aws_iam_role" "todo_app_amplify" {
  name        = "${var.stack_name}-amplify-role"
  description = "IAM role for Amplify"

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
  description = "IAM policy for Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
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

# IAM roles and policies for Lambda to interact with DynamoDB and publish metrics to CloudWatch
resource "aws_iam_role" "todo_app_lambda" {
  name        = "${var.stack_name}-lambda-role"
  description = "IAM role for Lambda"

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
  description = "IAM policy for Lambda"

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
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_app.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
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

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client(todo_app).id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_app.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_app.id
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.todo_app_add_item.function_name,
    aws_lambda_function.todo_app_get_item.function_name,
    aws_lambda_function.todo_app_get_all_items.function_name,
    aws_lambda_function.todo_app_update_item.function_name,
    aws_lambda_function.todo_app_complete_item.function_name,
    aws_lambda_function.todo_app_delete_item.function_name,
  ]
}
