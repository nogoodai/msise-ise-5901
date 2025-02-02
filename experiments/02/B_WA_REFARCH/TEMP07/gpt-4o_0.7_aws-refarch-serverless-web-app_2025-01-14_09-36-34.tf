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
  description = "The AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack for resource naming"
  default     = "myapp"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

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
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

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

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  provisioned_throughput {
    read_capacity_units  = 5
    write_capacity_units = 5
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.stack_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id = aws_apigatewayv2_api.api.id
  name   = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_log_group.arn
    format          = "$context.requestId: $context.status"
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id         = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer = aws_cognito_user_pool.user_pool.endpoint
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
  }
}

resource "aws_lambda_function" "lambda_function" {
  for_each = {
    "add_item"       = "POST /item",
    "get_item"       = "GET /item/{id}",
    "get_all_items"  = "GET /item",
    "update_item"    = "PUT /item/{id}",
    "complete_item"  = "POST /item/{id}/done",
    "delete_item"    = "DELETE /item/{id}"
  }

  function_name = "${var.stack_name}-${each.key}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

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

resource "aws_cloudwatch_log_group" "api_gw_log_group" {
  name              = "/aws/apigateway/${var.stack_name}"
  retention_in_days = 14
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.stack_name}-amplify-app"

  repository = var.github_repo
  oauth_token = var.github_token

  build_spec = jsonencode({
    version = 1
    applications = [{
      frontend = {
        phases = {
          preBuild = {
            commands = ["npm install"]
          }
          build = {
            commands = ["npm run build"]
          }
        }
        artifacts = {
          baseDirectory = "build"
          files = ["**/*"]
        }
        cache = {
          paths = ["node_modules/**/*"]
        }
      }
      appRoot = "/"
    }]
  })

  environment_variables = {
    "_LIVE_UPDATES" = "[]"
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id       = aws_amplify_app.amplify_app.id
  branch_name  = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gw_log_role" {
  name = "${var.stack_name}-api-gw-log-role"

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

  inline_policy {
    name = "cloudwatch-logs-policy"
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
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  inline_policy {
    name = "amplify-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "amplify:*",
          "s3:*",
          "cloudfront:*"
        ]
        Resource = "*"
      }]
    })
  }
}

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

  inline_policy {
    name = "dynamodb-access"
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
            "dynamodb:Scan",
            "dynamodb:Query"
          ]
          Resource = aws_dynamodb_table.todo_table.arn
        },
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Resource = "*"
        }
      ]
    })
  }
}

output "user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}
