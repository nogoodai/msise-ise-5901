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
  description = "The name of the stack."
  default     = "myapp-stack"
}

variable "domain_prefix" {
  description = "The domain prefix for Cognito."
  default     = "myapp-domain"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  policies {
    password_policy {
      minimum_length    = 6
      require_uppercase = true
      require_lowercase = true
      require_symbols   = false
      require_numbers   = false
    }
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "user-pool-client-${var.stack_name}"

  explicit_auth_flows         = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  supported_identity_providers = ["COGNITO"]
  
  callback_urls      = ["https://your-application/callback"]
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "openid", "profile"]
  allowed_oauth_flows_user_pool_client = true
  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain          = var.domain_prefix
  user_pool_id    = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

  hash_key   = "cognito-username"
  range_key  = "id"

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
  name        = "todo-api-${var.stack_name}"
  description = "API for managing to-do items"

  endpoint_configuration {
    types = ["EDGE"]
  }

  body = file("${path.module}/openapi.yaml")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  description         = "Production stage"
  client_certificate_id = aws_acm_certificate.certificate.id
}

resource "aws_lambda_function" "function_add_item" {
  function_name = "add-item-function-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  code {
    s3_bucket = "your-s3-bucket"
    s3_key    = "path/to/lambda/deployment.zip"
  }
}

resource "aws_iam_role" "lambda_exec" {
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

  inline_policy {
    name   = "dynamodb-access"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "dynamodb:PutItem",
            "dynamodb:GetItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem",
            "dynamodb:Scan"
          ]
          Resource = aws_dynamodb_table.todo_table.arn
        },
        {
          Effect = "Allow"
          Action = [
            "cloudwatch:PutMetricData"
          ]
          Resource = "*"
        }
      ]
    })
  }
}

resource "aws_iam_role" "api_gateway_exec" {
  name = "api-gateway-exec-role-${var.stack_name}"

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

  inline_policy {
    name   = "cloudwatch-logs-access"
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
}

resource "aws_amplify_app" "amplify" {
  name = "amplify-app-${var.stack_name}"
  repository = "https://github.com/your-user/your-repo.git"

  build_spec = file("${path.module}/amplify-buildspec.yml")
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.amplify.id
  branch_name = "master"
  enable_auto_build = true
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_url" {
  value = "${aws_api_gateway_rest_api.api.execution_arn}/${aws_api_gateway_stage.api_stage.stage_name}"
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify.default_domain
}
