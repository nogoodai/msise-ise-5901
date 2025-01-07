terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "application_name" {
  description = "Name of the application"
  default     = "serverless-web-app"
}

variable "stack_name" {
  description = "Name of the stack"
  default     = "prod"
}

resource "aws_cognito_user_pool" "user_pool" {
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
    Name        = "${var.application_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.application_name}-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "openid", "phone"]
  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

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

  provisioned_throughput {
    read_capacity  = 5
    write_capacity = 5
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_apigatewayv2_api" "api_gateway" {
  name          = "${var.application_name}-api"
  protocol_type = "HTTP"

  tags = {
    Name        = "api-gateway"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api_gateway.id
  name        = "prod"
  auto_deploy = true
  
  tags = {
    Name        = "api-stage"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${aws_apigatewayv2_api.api_gateway.name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "crud_function" {
  function_name = "${var.application_name}-function"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "lambda-function"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.application_name}-lambda-role"

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

  tags = {
    Name        = "lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.application_name}-lambda-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:*"
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
        Resource = "*"
      },
      {
        Action = "xray:PutTraceSegments"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "frontend_amplify_app" {
  name               = "${var.application_name}-frontend"
  repository         = "https://github.com/your-repo/your-app"
  enable_branch_auto_build = true
  
  build_spec = <<EOF
version: 1
applications:
  - frontend:
    - phases:
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

  tags = {
    Name        = "frontend-amplify-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id     = aws_amplify_app.frontend_amplify_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "amplify-branch"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-role"

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

  tags = {
    Name        = "api-gateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.application_name}-api-policy"
  role = aws_iam_role.api_gateway_role.id

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

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The Cognito User Pool ID"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_endpoint" {
  value       = aws_apigatewayv2_api.api_gateway.api_endpoint
  description = "The endpoint of the API Gateway"
}

output "amplify_app_url" {
  value       = aws_amplify_app.frontend_amplify_app.default_domain
  description = "The URL of the Amplify app"
}
