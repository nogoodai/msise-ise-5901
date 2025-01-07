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
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name to use for resource naming."
  default     = "prod"
}

variable "github_repo" {
  description = "The GitHub repository for the Amplify app."
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
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "user-pool-client-${var.stack_name}"

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "${var.stack_name}-auth"
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
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for managing to-do items."

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = jsonencode({
    openapi = "3.0.1"
    info    = {
      title   = "Todo API"
      version = "1.0"
    }
    paths = {
      "/item" = {
        get = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        }
        post = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        }
      }
      "/item/{id}" = {
        get = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        }
        put = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        }
        delete = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        }
        post = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        }
      }
    }
  })

  tags = {
    Name        = "todo-api-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  xray_tracing_enabled = true

  tags = {
    Name        = "todo-api-stage-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
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
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "get_item" {
  function_name = "get-item-${var.stack_name}"
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
    Name        = "get-item-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "get-all-items-${var.stack_name}"
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
    Name        = "get-all-items-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "update_item" {
  function_name = "update-item-${var.stack_name}"
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
    Name        = "update-item-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "complete_item" {
  function_name = "complete-item-${var.stack_name}"
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
    Name        = "complete-item-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "delete_item" {
  function_name = "delete-item-${var.stack_name}"
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
    Name        = "delete-item-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-app-${var.stack_name}"

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
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*

EOF

  oauth_token = data.aws_secretsmanager_secret_version.github_token.secret_string

  environment_variables = {
    _LIVE_UPDATES = "true"
  }

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"

  environment_variables = {
    _LIVE_UPDATES = "true"
  }

  tags = {
    Name        = "amplify-branch-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
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

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "api-gateway-policy-${var.stack_name}"
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
  name = "amplify-role-${var.stack_name}"

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
    Name        = "amplify-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "amplify-policy-${var.stack_name}"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
          "s3:*",
          "cloudfront:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = "github-token"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
