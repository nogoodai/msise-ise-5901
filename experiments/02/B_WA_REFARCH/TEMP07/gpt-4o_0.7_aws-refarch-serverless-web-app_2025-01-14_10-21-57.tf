terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources into."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack."
  default     = "prod"
}

variable "github_repo" {
  description = "The GitHub repository for the Amplify app."
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
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "user-pool-client-${var.stack_name}"

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  oauth {
    flows = ["authorization_code", "implicit"]
    scopes = ["email", "phone", "openid"]
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain      = "auth-${var.stack_name}"
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

  provisioned_throughput {
    read_capacity  = 5
    write_capacity = 5
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer = aws_cognito_user_pool.user_pool.endpoint
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
  }

  name = "cognito-authorizer-${var.stack_name}"
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "prod"
  auto_deploy = true
}

resource "aws_apigatewayv2_route" "api_routes" {
  for_each = {
    "POST /item"         = "add-item-function"
    "GET /item/{id}"     = "get-item-function"
    "GET /item"          = "get-all-items-function"
    "PUT /item/{id}"     = "update-item-function"
    "POST /item/{id}/done" = "complete-item-function"
    "DELETE /item/{id}"  = "delete-item-function"
  }

  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.key

  target = "integrations/${aws_lambda_function.lambda[each.value].arn}"
}

resource "aws_lambda_function" "lambda" {
  for_each = {
    "add-item-function" = "src/handlers/add-item.handler"
    "get-item-function" = "src/handlers/get-item.handler"
    "get-all-items-function" = "src/handlers/get-all-items.handler"
    "update-item-function" = "src/handlers/update-item.handler"
    "complete-item-function" = "src/handlers/complete-item.handler"
    "delete-item-function" = "src/handlers/delete-item.handler"
  }

  function_name = "${each.key}-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = each.value
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name = "lambda-dynamodb-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "dynamodb:PutItem",
            "dynamodb:GetItem",
            "dynamodb:Scan",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem"
          ]
          Resource = aws_dynamodb_table.todo_table.arn
        },
        {
          Effect = "Allow"
          Action = [
            "cloudwatch:PutMetricData"
          ]
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name = "api-gateway-logging-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
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

resource "aws_amplify_app" "amplify_app" {
  name  = "amplify-app-${var.stack_name}"
  repository = var.github_repo

  build_spec = <<-EOT
    version: 1.0
    applications:
      - frontend:
          phases:
            build:
              commands:
                - npm install
                - npm run build
          artifacts:
            baseDirectory: /build
            files:
              - '**/*'
    EOT

  oauth_token = var.github_oauth_token
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"

  enable_auto_build = true
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_url" {
  value = aws_apigatewayv2_stage.api_stage.invoke_url
}
