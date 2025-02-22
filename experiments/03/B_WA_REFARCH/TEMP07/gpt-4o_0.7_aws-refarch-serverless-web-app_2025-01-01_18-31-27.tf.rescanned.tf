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
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for resource identification."
  type        = string
  default     = "my-stack"
}

variable "github_repo" {
  description = "The GitHub repository for the Amplify app."
  type        = string
}

variable "amplify_branch" {
  description = "The branch to use for the Amplify app."
  type        = string
  default     = "master"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  }

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = jsonencode({ requestId = "$context.requestId", ip = "$context.identity.sourceIp", caller = "$context.identity.caller", user = "$context.identity.user", requestTime = "$context.requestTime", httpMethod = "$context.httpMethod", resourcePath = "$context.resourcePath", status = "$context.status", protocol = "$context.protocol", responseLength = "$context.responseLength" })
  }

  tags = {
    Name        = "api-stage-prod-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name = "/aws/apigateway/${aws_apigatewayv2_api.api.name}"

  retention_in_days = 7

  tags = {
    Name        = "api-gateway-logs-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id            = aws_apigatewayv2_api.api.id
  authorizer_type   = "JWT"
  identity_sources  = ["$request.header.Authorization"]
  name              = "cognito-authorizer"
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.user_pool.id}"
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "add-item-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = aws_apigatewayv2_api.api.execution_arn
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role-${var.stack_name}"

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

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess",
  ]

  tags = {
    Name        = "lambda-execution-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_app" "amplify_app" {
  name      = "amplify-${var.stack_name}"
  repository = var.github_repo
  oauth_token = var.github_oauth_token

  build_spec = <<EOF
version: 1
frontend:
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

  auto_branch_creation {
    patterns = ["*"]
  }

  tags = {
    Name        = "amplify-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

variable "github_oauth_token" {
  description = "GitHub OAuth token for Amplify app."
  type        = string
  sensitive   = true
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = var.amplify_branch
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

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

  policy {
    name = "api-gateway-cloudwatch-logs-policy"
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

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito User Pool."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB Table."
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_api.api.api_endpoint
  description = "The URL of the API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.amplify_app.id
  description = "The ID of the Amplify App."
}
