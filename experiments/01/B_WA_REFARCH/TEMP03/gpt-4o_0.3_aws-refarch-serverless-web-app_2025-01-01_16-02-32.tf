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
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the deployment stack."
  default     = "my-app-stack"
}

variable "github_repo" {
  description = "The GitHub repository for the Amplify app."
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

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
  name         = "${var.stack_name}-user-pool-client"

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "${var.stack_name}-auth"
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
          "uri": "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_all_items.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "post": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      }
    },
    "/item/{id}": {
      "get": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "put": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "delete": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "post": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      }
    }
  }
}
EOF
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  xray_tracing_enabled = true
  variables = {
    cognito_user_pool_arn = aws_cognito_user_pool.user_pool.arn
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api.body))
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan"

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
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

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
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"

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

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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
}

resource "aws_iam_policy" "api_gateway_policy" {
  name = "${var.stack_name}-api-gateway-policy"

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

resource "aws_iam_role_policy_attachment" "api_gateway_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.stack_name}-amplify-app"

  repository = var.github_repo
  oauth_token = var.github_token

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
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.api_stage.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
