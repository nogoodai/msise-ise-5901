terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack, used in naming resources."
  default     = "my-stack"
}

resource "aws_cognito_user_pool" "user_pool" {
  name   = "${var.stack_name}-user-pool"
  email_verification_subject = "Your verification code"
  email_verification_message = "Your verification code is {####}."

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                       = "${var.stack_name}-client"
  user_pool_id               = aws_cognito_user_pool.user_pool.id
  generate_secret            = false
  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls              = ["https://example.com/callback"]
  logout_urls                = ["https://example.com/signout"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  hash_key  = "cognito-username"
  range_key = "id"

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
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for the serverless application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "items_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                    = "${var.stack_name}-authorizer"
  rest_api_id             = aws_api_gateway_rest_api.api.id
  identity_source         = "method.request.header.Authorization"
  provider_arns           = [aws_cognito_user_pool.user_pool.arn]
  type                    = "COGNITO_USER_POOLS"
}

resource "aws_lambda_function" "get_item_function" {
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"

  memory_size = 1024
  timeout     = 60

  environment {
    variables = {
      TABLE_NAME       = aws_dynamodb_table.todo_table.name
      PRIMARY_KEY      = "cognito-username"
      SORT_KEY         = "id"
    }
  }

  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy_attachment" "lambda_dynamodb_policy" {
  name       = "${var.stack_name}-dynamodb-policy"
  policy_arn = aws_iam_policy.dynamodb_policy.arn
  roles      = [aws_iam_role.lambda_exec_role.name]
}

resource "aws_iam_policy" "dynamodb_policy" {
  name        = "${var.stack_name}-dynamodb-access"
  description = "DynamoDB access policy for Lambda functions."

  policy = data.aws_iam_policy_document.dynamodb_policy.json
}

data "aws_iam_policy_document" "dynamodb_policy" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Scan",
      "dynamodb:Query"
    ]

    resources = [aws_dynamodb_table.todo_table.arn]
  }
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.items.id
  http_method = aws_api_gateway_method.items_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_item_function.invoke_arn
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan"

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
  }
}

resource "aws_amplify_app" "frontend_app" {
  name  = "${var.stack_name}-amplify-app"

  source_code_repository = "https://github.com/your-repository/example"
  branch_name            = "master"
}

resource "aws_amplify_backend_environment" "prod_env" {
  app_id       = aws_amplify_app.frontend_app.id
  environment_name = "prod"
}

resource "aws_iam_role" "apigateway_cloudwatch" {
  name = "${var.stack_name}-apigateway-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.apigateway_assume_role.json
}

data "aws_iam_policy_document" "apigateway_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "apigateway_cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
  role       = aws_iam_role.apigateway_cloudwatch.name
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "Invoke URL for the API Gateway"
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "amplify_app_id" {
  description = "ID of the Amplify app"
  value       = aws_amplify_app.frontend_app.id
}
