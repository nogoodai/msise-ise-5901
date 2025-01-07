provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "stack_name" {
  default = "my-stack"
}

variable "env" {
  default = "prod"
}

variable "project" {
  default = "my-project"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                     = "${var.stack_name}-user-pool"
  email_configuration      = {
    email_type = "COGNITO_DEFAULT"
  }
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  username_attributes        = ["email"]
  auto_verified_attributes   = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.env
    Project     = var.project
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  name                                = "${var.stack_name}-user-pool-client"
  user_pool_id                        = aws_cognito_user_pool.user_pool.id
  generate_secret                     = false
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.stack_name}.${var.project}.com"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "table" {
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
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.env
    Project     = var.project
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name           = "${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = ["arn:aws:cognito-idp:${aws_region}::userpool/${aws_cognito_user_pool.user_pool.id}"]
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
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "get_items" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${var.stack_name}-add-item-lambda/invocations"
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${var.stack_name}-get-item-lambda/invocations"
}

resource "aws_api_gateway_integration" "get_items_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_items.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${var.stack_name}-get-all-items-lambda/invocations"
}

resource "aws_api_gateway_integration" "put_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${var.stack_name}-update-item-lambda/invocations"
}

resource "aws_api_gateway_integration" "post_item_done_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_item_done.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${var.stack_name}-complete-item-lambda/invocations"
}

resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${var.stack_name}-delete-item-lambda/invocations"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.post_item_integration, aws_api_gateway_integration.get_item_integration, aws_api_gateway_integration.get_items_integration, aws_api_gateway_integration.put_item_integration, aws_api_gateway_integration.post_item_done_integration, aws_api_gateway_integration.delete_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = var.env
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name}"
}

resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
  key_id        = aws_api_gateway_api_key.api_key.id
  key_type      = "API_KEY"
}

resource "aws_api_gateway_api_key" "api_key" {
  name = "${var.stack_name}-api-key"
}

# Lambda Functions
resource "aws_lambda_function" "add_item_lambda" {
  filename      = "add-item-lambda.zip"
  function_name = "${var.stack_name}-add-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "get_item_lambda" {
  filename      = "get-item-lambda.zip"
  function_name = "${var.stack_name}-get-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "get_all_items_lambda" {
  filename      = "get-all-items-lambda.zip"
  function_name = "${var.stack_name}-get-all-items-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "update_item_lambda" {
  filename      = "update-item-lambda.zip"
  function_name = "${var.stack_name}-update-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "complete_item_lambda" {
  filename      = "complete-item-lambda.zip"
  function_name = "${var.stack_name}-complete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "delete_item_lambda" {
  filename      = "delete-item-lambda.zip"
  function_name = "${var.stack_name}-delete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.stack_name}-lambda-exec-role"
  description = "Execution role for ${var.stack_name} lambdas"

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

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for ${var.stack_name} lambdas"

  policy      = jsonencode({
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
        Resource = aws_dynamodb_table.table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Amplify App
resource "aws_amplify_app" "app" {
  name        = "${var.stack_name}-app"
  description = "Amplify app for ${var.stack_name}"
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = "master"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.table.arn
}

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "api_gateway_deployment_id" {
  value = aws_api_gateway_deployment.deployment.id
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.add_item_lambda.function_name,
    aws_lambda_function.get_item_lambda.function_name,
    aws_lambda_function.get_all_items_lambda.function_name,
    aws_lambda_function.update_item_lambda.function_name,
    aws_lambda_function.complete_item_lambda.function_name,
    aws_lambda_function.delete_item_lambda.function_name,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}
