terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy the resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name to use for naming resources."
  default     = "my-app"
}

variable "github_repo" {
  description = "The GitHub repository for the Amplify app."
}

resource "aws_cognito_user_pool" "main" {
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

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "openid", "phone"]
  supported_identity_providers = ["COGNITO"]

  callback_urls = ["https://example.com/callback"]
  logout_urls   = ["https://example.com/logout"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
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

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = jsonencode({
    openapi = "3.0.1",
    info = {
      version = "1.0"
      title   = "${var.stack_name} API"
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
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_stage" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

  deployment_id = aws_api_gateway_deployment.main.id

  xray_tracing_enabled = true
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.main.stage_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.main.stage_name
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
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.stack_name}-lambda-policy"
  role   = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "main" {
  name               = "${var.stack_name}-amplify"
  repository         = var.github_repo
  oauth_token        = "<GITHUB_OAUTH_TOKEN>"

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
    Name        = "${var.stack_name}-amplify"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "main" {
  app_id            = aws_amplify_app.main.id
  branch_name       = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name   = "${var.stack_name}-api-gateway-policy"
  role   = aws_iam_role.api_gateway_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "amplify_policy" {
  name   = "${var.stack_name}-amplify-policy"
  role   = aws_iam_role.amplify_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "amplify:*",
          "s3:*"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.main.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}
