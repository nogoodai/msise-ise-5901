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
  description = "The stack name for resource naming."
  default     = "myapp"
}

variable "github_repo" {
  description = "The GitHub repository for the Amplify app."
}

resource "aws_cognito_user_pool" "auth" {
  name = "${var.stack_name}-user-pool"

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

resource "aws_cognito_user_pool_client" "auth_client" {
  user_pool_id = aws_cognito_user_pool.auth.id
  name         = "${var.stack_name}-user-pool-client"

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "auth_domain" {
  domain       = "${var.stack_name}-auth-domain"
  user_pool_id = aws_cognito_user_pool.auth.id
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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = <<EOF
{
  "swagger": "2.0",
  "info": {
    "title": "${var.stack_name} API",
    "version": "1.0"
  },
  "paths": {
    "/item": {
      "get": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_all_items.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "post": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      }
    },
    "/item/{id}": {
      "get": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "put": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "delete": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      }
    },
    "/item/{id}/done": {
      "post": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      }
    }
  }
}
EOF
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  variables = {
    cognito_user_pool_id = aws_cognito_user_pool.auth.id
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on  = [aws_api_gateway_integration.lambda_integration]
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan"

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
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  # Assume code is uploaded to S3 or use local file path
  filename = "path/to/lambda.zip"
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.stack_name}-get-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  filename = "path/to/lambda.zip"
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.stack_name}-get-all-items"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  filename = "path/to/lambda.zip"
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.stack_name}-update-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  filename = "path/to/lambda.zip"
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.stack_name}-complete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  filename = "path/to/lambda.zip"
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.stack_name}-delete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  filename = "path/to/lambda.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec-role"

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
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.stack_name}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

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

resource "aws_amplify_app" "frontend" {
  name = "${var.stack_name}-frontend"

  repository = var.github_repo

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
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.stack_name}-api-gateway-policy"
  role = aws_iam_role.api_gateway_role.id

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

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

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
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.auth.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
