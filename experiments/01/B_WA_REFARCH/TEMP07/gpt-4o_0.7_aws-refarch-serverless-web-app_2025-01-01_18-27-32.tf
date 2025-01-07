terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy into"
  default     = "us-east-1"
}

variable "environment" {
  description = "The environment for the application"
  default     = "production"
}

variable "project_name" {
  description = "The name of the project"
  default     = "serverless-web-app"
}

variable "stack_name" {
  description = "The stack name for resource naming"
  default     = "prod"
}

resource "aws_cognito_user_pool" "app_user_pool" {
  name = "${var.project_name}-user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "cognito-user-pool-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "app_user_pool_client" {
  name         = "${var.project_name}-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "openid", "phone"]
  generate_secret            = false
  callback_urls              = ["https://example.com/callback"]
  logout_urls                = ["https://example.com/logout"]

  tags = {
    Name        = "cognito-user-pool-client-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "app_user_pool_domain" {
  domain      = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id

  tags = {
    Name        = "cognito-user-pool-domain-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
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

  tags = {
    Name        = "dynamodb-todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = "${var.project_name}-api-${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  tags = {
    Name        = "api-gateway-stage-prod"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = "${uuid()}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.project_name}-usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  tags = {
    Name        = "api-gateway-usage-plan-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-add-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "lambda-add-item-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_amplify_app" "app" {
  name  = "${var.project_name}-${var.stack_name}"
  repository = "https://github.com/user/repo"

  build_spec = <<EOF
version: 0.1
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
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "amplify-branch-master"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "iam-role-lambda-exec-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:DeleteItem"
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      },
      {
        Action = "xray:PutTelemetryRecords"
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "iam-role-api-gateway-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.project_name}-api-gateway-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "logs:*"
        Effect = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "iam-role-amplify-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.project_name}-amplify-policy-${var.stack_name}"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
          "s3:*",
          "cloudfront:*",
          "route53:*"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.app_user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_url" {
  value = aws_amplify_app.app.default_domain
}
