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
  description = "The AWS region to deploy the resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for resource identification"
  type        = string
  default     = "prod"
}

variable "github_repository" {
  description = "GitHub repository for Amplify frontend source"
  type        = string
}

variable "cognito_domain_prefix" {
  description = "The custom domain prefix for Cognito"
  type        = string
  default     = "app-${var.stack_name}"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  username_attributes          = ["email"]
  auto_verified_attributes     = ["email"]
  password_policy {
    minimum_length      = 6
    require_uppercase   = true
    require_lowercase   = true
    require_symbols     = false
    require_numbers     = false
  }
  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "openid", "phone"]
  generate_secret           = false
  
  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = var.cognito_domain_prefix
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = "api-${var.stack_name}"

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "UsagePlan-${var.stack_name}"

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
    Name        = "UsagePlan-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_lambda_function" "crud_function" {
  runtime          = "nodejs12.x"
  handler          = "index.handler"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("function.zip") // Assume deployment package is prepared

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    // Fill appropriately if needed based on your network setup
  }

  tags = {
    Name        = "lambda-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.crud_function.function_name}"
  retention_in_days = 14

  tags = {
    Name        = "lambda-log-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_appsync_graphql_api" "graphql_api" {
  name = "GraphQLAPI-${var.stack_name}"
  authentication_type = "AMAZON_COGNITO_USER_POOLS"
  // Additional configurations based on specific requirements
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-app-${var.stack_name}"
  
  source_code_repository = var.github_repository

  build_spec = <<-EOT
    version: 1.0
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
  EOT

  environment_variables = {
    NODE_ENV = "production"
  }

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_amplify_branch" "master" {
  app_id     = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "master-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_iam_role" "lambda_execution" {
  name = "lambda-execution-${var.stack_name}"

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
    Name        = "lambda-execution-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy-${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach_policy" {
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
  role       = aws_iam_role.lambda_execution.name
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
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "apigateway-role-${var.stack_name}"

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
    Name        = "apigateway-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_iam_policy" "apigateway_cw_policy" {
  name = "apigateway-cw-policy-${var.stack_name}"

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
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apigateway_attach_policy" {
  policy_arn = aws_iam_policy.apigateway_cw_policy.arn
  role       = aws_iam_role.api_gateway_role.name
}

output "user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "The invoke URL of the API Gateway"
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "amplify_app_id" {
  description = "The ID of the Amplify app"
  value       = aws_amplify_app.amplify_app.id
}
