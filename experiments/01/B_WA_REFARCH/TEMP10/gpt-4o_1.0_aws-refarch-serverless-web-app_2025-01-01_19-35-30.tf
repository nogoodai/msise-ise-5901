terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources into."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack."
  default     = "prod-stack"
}

variable "amplify_source_repo" {
  description = "The GitHub repository URL for the Amplify App source."
  default     = "https://github.com/example/repo.git"
}

variable "amplify_branch" {
  description = "The branch to build and deploy for the Amplify App."
  default     = "master"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id          = aws_cognito_user_pool.user_pool.id
  name                  = "user-pool-client-${var.stack_name}"
  generate_secret       = false
  allowed_oauth_scopes  = ["email", "phone", "openid"]
  allowed_oauth_flows   = ["authorization_code", "implicit"]
  callback_urls         = ["https://example.com/callback"]
  explicit_auth_flows   = ["ALLOW_REFRESH_TOKEN_AUTH"]

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
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
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for managing todo items"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                    = "cognito-authorizer"
  rest_api_id             = aws_api_gateway_rest_api.api.id
  type                    = "COGNITO_USER_POOLS"
  provider_arns           = [aws_cognito_user_pool.user_pool.arn]
  identity_source         = "method.request.header.Authorization"
}

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_models = {
    "application/json" = "Empty"
  }
}

resource "aws_lambda_function" "add_item" {
  filename         = "path/to/lambda_zip/add_item.zip"
  function_name    = "add-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  publish          = true
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "add-item-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_lambda_permission" "api_invocation" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/POST/item"
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.items.id
  http_method = aws_api_gateway_method.post_item.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.add_item.invoke_arn
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.post_item_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_apigatewayv2_stage" "prod_stage" {
  api_id      = aws_api_gateway_rest_api.api.id
  name        = "prod"
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  tags = {
    Name        = "prod-stage"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_apigatewayv2_usage_plan" "usage_plan" {
  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "usage-plan"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_appsync_graphql_api" "amplify_app" {
  name = "amplify-app-${var.stack_name}"
  authentication_type = "API_KEY"
}

resource "aws_amplify_app" "amplify_app" {
  name             = "amplify-app-${var.stack_name}"
  repository       = var.amplify_source_repo
  oauth_token      = var.oauth_token
  build_spec       = file("amplify-build-spec.yml")

  auto_branch_creation_config {
    enable_auto_build  = true
    enable_auto_branch_creation = true
    enable_auto_build_on_pull_requests = true
    pull_request_preview_enabled = true
    stage = "DEVELOPMENT"
  }

  branch {
    branch_name = var.amplify_branch
  }

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "sts:AssumeRole"
        Effect   = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessApp"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito User Pool."
}

output "api_gateway_url" {
  value       = aws_api_gateway_rest_api.api.execution_arn
  description = "The URL for the deployed API Gateway."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table."
}

output "amplify_app_id" {
  value       = aws_amplify_app.amplify_app.id
  description = "The ID of the Amplify application."
}
