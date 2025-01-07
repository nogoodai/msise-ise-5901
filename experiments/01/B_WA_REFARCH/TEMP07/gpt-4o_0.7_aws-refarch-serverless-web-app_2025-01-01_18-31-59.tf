terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for resource naming"
  default     = "my-stack"
}

variable "application_name" {
  description = "The application name for naming conventions"
  default     = "my-app"
}

resource "aws_cognito_user_pool" "auth" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

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
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "auth_client" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.auth.id

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "auth_domain" {
  domain      = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.auth.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  hash_key     = "cognito-username"
  range_key    = "id"

  attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  billing_mode = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.application_name}-${var.stack_name}-api"
  protocol_type = "HTTP"
  
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id   = aws_apigatewayv2_api.api.id
  name     = "prod"
  auto_deploy = true
  
  tags = {
    Stage      = "prod"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id       = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.auth_client.id]
    issuer   = aws_cognito_user_pool.auth.endpoint
  }

  name = "${var.application_name}-authorizer"
}

resource "aws_lambda_function" "lambda_function" {
  filename         = "function.zip"
  function_name    = "${var.application_name}-${var.stack_name}-lambda"
  role             = aws_iam_role.lambda_exec.arn
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
    Name        = "${var.application_name}-${var.stack_name}-lambda"
    Environment = "production"
    Project     = var.application_name
  }

  dynamic "event" {
    for_each = ["POST /item", "GET /item/{id}", "GET /item", "PUT /item/{id}", "POST /item/{id}/done", "DELETE /item/{id}"]
    content {
      source_arn = aws_apigatewayv2_integration.lambda_integration.arn
      statement_id = base64sha256(event.value)
    }
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.lambda_function.invoke_arn

  tags = {
    Name        = "${var.application_name}-lambda-integration"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.application_name}-${var.stack_name}-lambda-exec"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-exec"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.application_name}-${var.stack_name}-lambda-policy"
  description = "IAM policy for lambda to access DynamoDB and CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_amplify_app" "frontend" {
  name = "${var.application_name}-${var.stack_name}-amplify"

  repository    = "https://github.com/username/repository"
  oauth_token   = var.github_token

  build_spec = <<EOF
version: 1
frontend:
  phases:
    build:
      commands:
        - npm install
        - npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*

EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "frontend_branch" {
  app_id = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-master"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-role"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
  description = "IAM policy for API Gateway to write CloudWatch logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-${var.stack_name}-amplify-role"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.application_name}-${var.stack_name}-amplify-policy"
  description = "IAM policy for Amplify to manage resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:DeleteApp",
          "amplify:UpdateApp",
          "amplify:CreateBranch",
          "amplify:DeleteBranch",
          "amplify:UpdateBranch"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.auth.id
}

output "cognito_user_pool_client_id" {
  description = "The ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.auth_client.id
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB Table"
  value       = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_id" {
  description = "The ID of the API Gateway"
  value       = aws_apigatewayv2_api.api.id
}

output "amplify_app_id" {
  description = "The ID of the Amplify App"
  value       = aws_amplify_app.frontend.id
}
