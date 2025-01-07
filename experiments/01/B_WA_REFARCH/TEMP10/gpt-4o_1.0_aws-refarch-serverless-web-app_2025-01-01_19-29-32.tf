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
  description = "The AWS region to deploy resources."
  type        = string
  default     = "us-west-2"
}

variable "stack_name" {
  description = "The stack name for resource naming."
  type        = string
  default     = "my-stack"
}

variable "amplify_github_token" {
  description = "The GitHub personal access token for Amplify."
  type        = string
  sensitive   = true
}

variable "amplify_github_repo" {
  description = "The GitHub repository for the Amplify app."
  type        = string
  default     = "user/repo"
}

resource "aws_cognito_user_pool" "main" {
  name             = "app-user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "app-user-pool-client-${var.stack_name}"
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret     = false
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  write_capacity = 5
  read_capacity  = 5

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

resource "aws_apigatewayv2_api" "main" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
  }
}

resource "aws_apigatewayv2_stage" "main" {
  api_id = aws_apigatewayv2_api.main.id
  name   = "prod"
  auto_deploy = true
}

resource "aws_apigatewayv2_route" "add_item" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /item"
}

resource "aws_apigatewayv2_route" "get_item" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /item/{id}"
}

resource "aws_apigatewayv2_route" "get_all_items" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /item"
}

resource "aws_apigatewayv2_route" "update_item" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "PUT /item/{id}"
}

resource "aws_apigatewayv2_route" "complete_item" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /item/{id}/done"
}

resource "aws_apigatewayv2_route" "delete_item" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "DELETE /item/{id}"
}

resource "aws_lambda_function" "crud" {
  function_name = "lambda-function-${var.stack_name}"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-execution-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda-dynamodb-policy-${var.stack_name}"
  description = "Policy providing access to DynamoDB for Lambda functions"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo.arn
      },
      {
        Effect   = "Allow"
        Action   = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_amplify_app" "main" {
  name                = "amplify-app-${var.stack_name}"
  repository          = var.amplify_github_repo
  oauth_token         = var.amplify_github_token
  build_spec          = jsonencode({
    version = "1.0"
    applications = [
      {
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
            baseDirectory = "/build"
            files = ["**/*"]
          }
        }
      }
    ]
  })
  default_domain      = false
  enable_auto_build   = true
  branch_auto_build_proc {
    branch_name     = "master"
    auto_build      = true
  }
}

resource "aws_iam_role" "apigateway_cloudwatch" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "apigateway_cloudwatch_policy" {
  name        = "apigateway-cloudwatch-policy-${var.stack_name}"
  description = "Policy to allow API Gateway to log to CloudWatch"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_apigw_policy" {
  role       = aws_iam_role.apigateway_cloudwatch.name
  policy_arn = aws_iam_policy.apigateway_cloudwatch_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "api_gateway_url" {
  value = aws_apigatewayv2_stage.main.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}
