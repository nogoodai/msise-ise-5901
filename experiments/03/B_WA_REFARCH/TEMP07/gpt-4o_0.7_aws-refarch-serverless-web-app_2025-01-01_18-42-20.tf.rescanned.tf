terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack"
  type        = string
  default     = "myapp"
}

variable "application_name" {
  description = "The name of the application"
  type        = string
  default     = "todo-app"
}

variable "github_oauth_token" {
  description = "GitHub OAuth token for AWS Amplify"
  type        = string
  sensitive   = true
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "OPTIONAL"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.application_name}-${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret     = true

  o_auth {
    flows = {
      authorization_code_grant = true
      implicit_code_grant      = true
    }

    scopes = ["email", "openid", "phone"]
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API for managing to-do items"

  body = <<EOF
{
  "swagger": "2.0",
  "info": {
    "version": "1.0",
    "title": "ToDo API"
  },
  "paths": {
    "/item": {
      "get": {
        "x-amazon-apigateway-integration": {
          "httpMethod": "GET",
          "type": "AWS_PROXY",
          "uri": "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/\${aws_lambda_function.get_all_items.arn}/invocations"
        }
      },
      "post": {
        "x-amazon-apigateway-integration": {
          "httpMethod": "POST",
          "type": "AWS_PROXY",
          "uri": "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/\${aws_lambda_function.add_item.arn}/invocations"
        }
      }
    }
  }
}
EOF

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access_log.arn
    format          = "$context.identity.sourceIp - $context.identity.caller - $context.requestId - [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.responseLatency $context.integrationLatency"
  }

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-stage"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "api_access_log" {
  name = "/aws/apigateway/${var.application_name}-${var.stack_name}-access-log"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-access-log"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_rest_api.api]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.application_name}-${var.stack_name}-usage-plan"

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
    Name        = "${var.application_name}-${var.stack_name}-usage-plan"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.application_name}-${var.stack_name}-add-item"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  filename         = "path_to_your_lambda_function.zip"
  source_code_hash = filebase64sha256("path_to_your_lambda_function.zip")

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-add-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.application_name}-${var.stack_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-exec"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.dynamodb_crud_policy.arn
}

resource "aws_iam_policy" "dynamodb_crud_policy" {
  name = "${var.application_name}-${var.stack_name}-dynamodb-crud"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-dynamodb-crud-policy"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_amplify_app" "amplify_app" {
  name        = "${var.application_name}-${var.stack_name}-amplify"
  repository  = "https://github.com/your-repo/your-project"
  oauth_token = var.github_oauth_token

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
  app_id          = aws_amplify_app.amplify_app.id
  branch_name     = "master"
  enable_auto_build = true
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito User Pool"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_url" {
  value       = aws_api_gateway_stage.api_stage.invoke_url
  description = "The URL of the API Gateway"
}

output "amplify_app_id" {
  value       = aws_amplify_app.amplify_app.id
  description = "The ID of the AWS Amplify app"
}
