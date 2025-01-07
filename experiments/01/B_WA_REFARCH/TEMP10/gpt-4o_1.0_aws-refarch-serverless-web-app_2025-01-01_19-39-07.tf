terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy the resources."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the application stack."
  default     = "myapp-stack"
}

variable "amplify_source_repo" {
  description = "The GitHub repository URL for the Amplify app."
  default     = "https://github.com/user/repo"
}

resource "aws_cognito_user_pool" "main" {
  name = "user-pool-${var.stack_name}"

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

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  o_auth_flows = ["admin_no_srp_auth", "authorization_code", "implicit"]
  allowed_o_auth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${var.application_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
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

resource "aws_apigateway_rest_api" "main" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for the todo application."

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = file("swagger.yaml")
}

resource "aws_apigateway_stage" "prod" {
  rest_api_id = aws_apigateway_rest_api.main.id
  stage_name  = "prod"

  method_settings {
    method_path = "*/*"
    metrics_enabled = true
    logging_level   = "INFO"
    data_trace_enabled = true

    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }
}

resource "aws_apigateway_usage_plan" "main" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_apigateway_rest_api.main.id
    stage  = aws_apigateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit  = 100
    rate_limit   = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "crud" {
  filename         = "function.zip"
  function_name    = "crud-function-${var.stack_name}"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_exec.arn
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
  
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  provisioned_concurrent_executions = 1
}

resource "aws_amplify_app" "main" {
  name                = "amplify-${var.stack_name}"
  repository          = var.amplify_source_repo
  oauth_token         = "your-oauth-token"

  build_spec = <<-EOT
    version: 1
    applications:
      - frontend:
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

  default_branch = "master"
}

resource "aws_amplify_branch" "main" {
  app_id             = aws_amplify_app.main.id
  branch_name        = "master"
  enable_auto_build  = true
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-${var.stack_name}"

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
  name = "lambda-dynamodb-${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.main.arn
      }
    ]
  })
}

resource "aws_iam_policy" "cloudwatch_policy" {
  name = "cloudwatch-${var.stack_name}"

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

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.cloudwatch_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name = "amplify-exec-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.${var.aws_region}.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "amplify_policy" {
  name = "amplify-${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
          "codedeploy:*",
          "cloudwatch:*",
          "logs:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "lambda_function_arn" {
  value = aws_lambda_function.crud.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "api_gateway_url" {
  value = aws_apigateway_rest_api.main.execution_arn
}
