terraform {
  required_providers {
    aws = ">= 5.1.0"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  description = "The name of the project"
  default     = "serverless-web-app"
}

variable "stack_name" {
  description = "The current stack name"
  default     = "prod"
}

variable "github_repo_url" {
  description = "GitHub repository URL for Amplify"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

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
  name         = "${var.project_name}-${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = [
    "ALLOW_AUTH_CODE_AUTH",
    "ALLOW_IMPLICIT_FLOW"
  ]

  allowed_oauth_flows_user_pool_client = true

  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.project_name}-${var.stack_name}"
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
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-${var.stack_name}-api"
  description = "API for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = <<EOF
{
  "swagger": "2.0",
  "info": {
    "title": "${var.project_name} API",
    "version": "1.0"
  },
  "basePath": "/",
  "schemes": ["https"],
  "paths": {
    "/item": {
      "get": {
        "responses": {
          "200": {
            "description": "Get all items"
          }
        },
        "x-amazon-apigateway-integration": {
          "uri": "${aws_lambda_function.get_all_items.invoke_arn}",
          "passthroughBehavior": "when_no_match",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "post": {
        "responses": {
          "200": {
            "description": "Add an item"
          }
        },
        "x-amazon-apigateway-integration": {
          "uri": "${aws_lambda_function.add_item.invoke_arn}",
          "passthroughBehavior": "when_no_match",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      }
    },
    "/item/{id}": {
      "get": {
        "responses": {
          "200": {
            "description": "Get an item"
          }
        },
        "x-amazon-apigateway-integration": {
          "uri": "${aws_lambda_function.get_item.invoke_arn}",
          "passthroughBehavior": "when_no_match",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "put": {
        "responses": {
          "200": {
            "description": "Update an item"
          }
        },
        "x-amazon-apigateway-integration": {
          "uri": "${aws_lambda_function.update_item.invoke_arn}",
          "passthroughBehavior": "when_no_match",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "delete": {
        "responses": {
          "200": {
            "description": "Delete an item"
          }
        },
        "x-amazon-apigateway-integration": {
          "uri": "${aws_lambda_function.delete_item.invoke_arn}",
          "passthroughBehavior": "when_no_match",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "post": {
        "x-amazon-apigateway-any-method": {
          "responses": {
            "200": {
              "description": "Complete an item"
            }
          },
          "x-amazon-apigateway-integration": {
            "uri": "${aws_lambda_function.complete_item.invoke_arn}",
            "passthroughBehavior": "when_no_match",
            "httpMethod": "POST",
            "type": "aws_proxy"
          }
        }
      }
    }
  }
}
EOF

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_stage" "prod_stage" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  xray_tracing_enabled = true
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.project_name}-${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod_stage.stage_name
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
  function_name = "${var.project_name}-add-item"
  filename      = "path-to-zip-file"
  handler       = "index.handler"
  runtime       = "nodejs12.x"

  memory_size = 1024
  timeout     = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.project_name}-get-item"
  filename      = "path-to-zip-file"
  handler       = "index.handler"
  runtime       = "nodejs12.x"

  memory_size = 1024
  timeout     = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.project_name}-get-all-items"
  filename      = "path-to-zip-file"
  handler       = "index.handler"
  runtime       = "nodejs12.x"

  memory_size = 1024
  timeout     = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.project_name}-update-item"
  filename      = "path-to-zip-file"
  handler       = "index.handler"
  runtime       = "nodejs12.x"

  memory_size = 1024
  timeout     = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.project_name}-complete-item"
  filename      = "path-to-zip-file"
  handler       = "index.handler"
  runtime       = "nodejs12.x"

  memory_size = 1024
  timeout     = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.project_name}-delete-item"
  filename      = "path-to-zip-file"
  handler       = "index.handler"
  runtime       = "nodejs12.x"

  memory_size = 1024
  timeout     = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-${var.stack_name}-lambda-exec-role"

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
    Name        = "${var.project_name}-${var.stack_name}-lambda-exec-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda_exec_policy" {
  name = "${var.project_name}-${var.stack_name}-lambda-exec-policy"

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
      },
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = "xray:PutTelemetryRecords",
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_exec_policy.arn
}

resource "aws_amplify_app" "frontend" {
  name = "${var.project_name}-${var.stack_name}-frontend"

  repository = var.github_repo_url
  oauth_token = "your-oauth-token" # Use a secret manager to handle sensitive information
  
  environment_variables = {
    _LIVE_UPDATES = true
  }

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
    paths: []
EOF

  branch {
    branch_name = "master"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-role"

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
    Name        = "${var.project_name}-${var.stack_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-policy"

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
  name = "${var.project_name}-${var.stack_name}-amplify-role"

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
    Name        = "${var.project_name}-${var.stack_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name = "${var.project_name}-${var.stack_name}-amplify-policy"

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

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_invoke_url" {
  description = "API Gateway invoke URL"
  value       = "${aws_api_gateway_rest_api.api.execution_arn}/prod"
}

output "amplify_app_id" {
  description = "ID of the Amplify App"
  value       = aws_amplify_app.frontend.app_id
}
