terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack for resource naming."
  default     = "my-stack"
}

variable "github_repo" {
  description = "The GitHub repository for the Amplify app."
  default     = "user/repo"
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
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
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

  provisioned_throughput {
    read_capacity  = 5
    write_capacity = 5
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API for the serverless web application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  tags = {
    Name        = "api-stage-prod-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
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
    Name        = "usage-plan-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
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
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "add-item-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.dynamodb_policy.arn
}

resource "aws_iam_policy" "dynamodb_policy" {
  name = "dynamodb-policy-${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = "cloudwatch:PutMetricData"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-app-${var.stack_name}"

  repository = "https://github.com/${var.github_repo}"

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
  cache:
    paths:
      - node_modules/**/*

EOF

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"

  tags = {
    Name        = "amplify-branch-master-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "amplify-role-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "The URL of the API Gateway."
  value       = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  description = "The ID of the Amplify App."
  value       = aws_amplify_app.amplify_app.id
}
