terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources to"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "The name of the stack"
  default     = "my-app"
}

variable "github_repository" {
  description = "The GitHub repository for the Amplify app"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  policies {
    password_policy {
      minimum_length    = 6
      require_uppercase = true
      require_lowercase = true
      require_symbols   = false
      require_numbers   = false
    }
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                       = "${var.stack_name}-client"
  user_pool_id               = aws_cognito_user_pool.user_pool.id
  generate_secret            = false
  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "openid", "phone"]
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain      = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity   = 5
  write_capacity  = 5

  hash_key   = "cognito-username"
  range_key  = "id"

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
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_api" "api_gateway" {
  name          = "${var.stack_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api_gateway.id
  name        = "prod"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

resource "aws_lambda_function" "crud_functions" {
  for_each = {
    "add_item"       = "addItem.handler"
    "get_item"       = "getItem.handler"
    "get_all_items"  = "getAllItems.handler"
    "update_item"    = "updateItem.handler"
    "complete_item"  = "completeItem.handler"
    "delete_item"    = "deleteItem.handler"
  }

  filename         = "code/${each.key}.zip"
  function_name    = "${var.stack_name}-${each.key}"
  handler          = each.value
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.stack_name}-lambda-policy"
  role   = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = "logs:*"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_amplify_app" "amplify_app" {
  name         = "${var.stack_name}-frontend"
  repository   = var.github_repository
  oauth_token  = var.oauth_token
  
  build_spec   = "version: 0.1\nfrontend:\n  phases:\n    preBuild:\n      commands:\n        - npm install\n    build:\n      commands:\n        - npm run build\n  artifacts:\n    baseDirectory: build\n    files:\n      - '**/*'\n  cache:\n    paths:\n      - node_modules/**\n\n"

  environment_variables = {
    "_LIVE_UPDATES": "false"
  }
}

resource "aws_amplify_branch" "master" {
  app_id   = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "apigw_logging_role" {
  name = "${var.stack_name}-apigw-logging"

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

resource "aws_iam_policy" "apigw_logging_policy" {
  name   = "${var.stack_name}-apigw-logging-policy"
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

resource "aws_iam_role_policy_attachment" "apigateway_logging" {
  role       = aws_iam_role.apigw_logging_role.name
  policy_arn = aws_iam_policy.apigw_logging_policy.arn
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

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}

output "lambda_function_arns" {
  value = [for fn in aws_lambda_function.crud_functions : fn.arn]
}
