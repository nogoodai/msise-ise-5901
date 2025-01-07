terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack"
  default     = "prod-stack"
}

variable "git_repo_url" {
  description = "The GitHub repository URL for the Amplify app"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                     = "user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "cognito-user-pool"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "pool-client-${var.stack_name}"
  generate_secret = false

  allowed_oauth_flows            = ["code", "implicit"]
  allowed_oauth_scopes           = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "cognito-user-pool-client"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "domain" {
  domain        = "auth-${var.stack_name}"
  user_pool_id  = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "dynamodb-todo-table"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for managing to-do items"

  tags = {
    Name        = "api-gateway"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  identity_source = "method.request.header.Authorization"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id     = aws_api_gateway_deployment.api_deployment.id
  rest_api_id       = aws_api_gateway_rest_api.api.id
  stage_name        = "prod"
  description       = "Prod stage"
  data_trace_enabled = true
  logging_level     = "INFO"

  tags = {
    Name        = "api-gateway-stage"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id   = aws_api_gateway_rest_api.api.id
    stage    = aws_api_gateway_stage.api_stage.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "lambda_functions" {
  for_each = {
    "add_item"     : "POST /item",
    "get_item"     : "GET /item/{id}",
    "get_all_items": "GET /item",
    "update_item"  : "PUT /item/{id}",
    "complete_item": "POST /item/{id}/done",
    "delete_item"  : "DELETE /item/{id}"
  }

  filename         = "path_to_zip/${each.key}.zip"
  function_name    = "${each.key}-${var.stack_name}"
  handler          = "${each.key}.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  role             = aws_iam_role.lambda_exec_role.arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "lambda-${each.key}"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

resource "aws_amplify_app" "frontend_app" {
  name              = "frontend-${var.stack_name}"
  repository        = var.git_repo_url
  oauth_token       = "YOUR_GITHUB_OAUTH_TOKEN"
  build_spec        = file("amplify_build_spec.yml")

  auto_branch_creation_config {
    enable_auto_build = true
    stage             = "PRODUCTION"
  }

  tags = {
    Name        = "amplify-app"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

resource "aws_amplify_branch" "main_branch" {
  app_id     = aws_amplify_app.frontend_app.id
  branch_name = "master"

  enable_auto_build = true

  tags = {
    Name        = "amplify-branch"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role"

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
    Name        = "lambda-exec-role"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-policy-${var.stack_name}"
  description = "Policy for Lambda to interact with DynamoDB and CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
        Effect = "Allow"
        Resource = "${aws_dynamodb_table.todo_table.arn}"
      },
      {
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  policy_arn = aws_iam_policy.lambda_policy.arn
  role       = aws_iam_role.lambda_exec_role.name
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role"

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
    Name        = "api-gateway-role"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  role    = aws_iam_role.api_gateway_role.id
  policy  = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "logs:*"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role"

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
    Name        = "amplify-role"
    Environment = var.stack_name
    Project     = "serverless-webapp"
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend_app.id
}
