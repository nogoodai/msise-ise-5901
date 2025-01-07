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
  description = "The stack name for resource naming."
  type        = string
}

variable "github_repo" {
  description = "The GitHub repository URL for the Amplify app."
  type        = string
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false

  o_auth_flows {
    authorization_code_grant = true
    implicit_code_grant      = true
  }

  allowed_o_auth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-domain"
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

resource "aws_apigatewayv2_api" "api_gateway" {
  name          = "${var.stack_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id    = aws_apigatewayv2_api.api_gateway.id
  name      = "prod"
  auto_deploy = true
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id          = aws_apigatewayv2_api.api_gateway.id
  authorizer_type = "JWT"
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = aws_cognito_user_pool.user_pool.endpoint
  }
  identity_sources = ["$request.header.Authorization"]
}

resource "aws_apigatewayv2_route" "api_routes" {
  for_each = {
    "POST/item"       = "POST"
    "GET/item/{id}"   = "GET"
    "GET/item"        = "GET"
    "PUT/item/{id}"   = "PUT"
    "POST/item/{id}/done" = "POST"
    "DELETE/item/{id}" = "DELETE"
  }

  api_id    = aws_apigatewayv2_api.api_gateway.id
  route_key = each.key

  authorizer_id = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  for_each = {
    "POST/item"         = aws_lambda_function.add_item.arn
    "GET/item/{id}"     = aws_lambda_function.get_item.arn
    "GET/item"          = aws_lambda_function.get_all_items.arn
    "PUT/item/{id}"     = aws_lambda_function.update_item.arn
    "POST/item/{id}/done" = aws_lambda_function.complete_item.arn
    "DELETE/item/{id}"  = aws_lambda_function.delete_item.arn
  }

  api_id             = aws_apigatewayv2_api.api_gateway.id
  integration_uri    = each.value
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec_role.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

# Additional lambda functions (get_item, get_all_items, etc.) would be defined similarly to add_item...

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name   = "${var.stack_name}-lambda-dynamodb-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = "cloudwatch:PutMetricData"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_amplify_app" "amplify_app" {
  name  = "${var.stack_name}-amplify-app"
  repository = var.github_repo
  oauth_token = var.github_oauth_token

  build_spec = <<EOF
version: 1
applications:
  - frontend:
      phases:
        preBuild:
          commands:
            - npm install
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: /build
        files:
          - '**/*'
EOF
}

resource "aws_amplify_branch" "master_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_logging_role" {
  name = "${var.stack_name}-api-gateway-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "api_gateway_logging_policy" {
  name   = "${var.stack_name}-api-gateway-logging-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy_attachment" "api_gateway_logging_attach" {
  name       = "${var.stack_name}-api-gateway-logging-attach"
  roles      = [aws_iam_role.api_gateway_logging_role.name]
  policy_arn = aws_iam_role_policy.api_gateway_logging_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_apigatewayv2_api.api_gateway.api_endpoint
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
