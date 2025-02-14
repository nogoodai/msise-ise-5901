terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "stack_name" {
  description = "Name of the application stack"
  type        = string
  default     = "myapp"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify"
  type        = string
  default     = "https://github.com/example/repo"
}

resource "aws_cognito_user_pool" "app_user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_symbols   = true
    require_numbers   = true
  }

  mfa_configuration = "ON"

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "app_domain" {
  domain      = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
}

resource "aws_cognito_user_pool_client" "app_user_pool_client" {
  name         = "app-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = true
  allowed_oauth_flows_user_pool_client = true
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
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_api" "app_api" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://myapp.example.com"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
  }

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.app_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.app_user_pool_client.id]
    issuer   = aws_cognito_user_pool.app_user_pool.endpoint
  }
}

resource "aws_apigatewayv2_stage" "prod_stage" {
  api_id      = aws_apigatewayv2_api.app_api.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_log_group.arn
    format          = jsonencode({
      requestId = "$context.requestId",
      ipAddress = "$context.identity.sourceIp",
      userAgent = "$context.identity.userAgent",
      requestTime = "$context.requestTime",
      httpMethod = "$context.httpMethod",
      resourcePath = "$context.resourcePath",
      status = "$context.status",
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name        = "prod-stage-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "api_gw_log_group" {
  name              = "/aws/apigateway/${aws_apigatewayv2_api.app_api.name}"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.log_group_key.arn

  tags = {
    Name        = "api-gw-log-group-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_kms_key" "log_group_key" {
  description = "KMS key for CloudWatch log group encryption"
}

resource "aws_lambda_function" "add_item_function" {
  function_name = "add-item-${var.stack_name}"
  runtime       = "nodejs14.x"
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

  tags = {
    Name        = "add-item-function-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_permission" "api_gw_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item_function.arn
  principal     = "apigateway.amazonaws.com"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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

  inline_policy {
    name = "dynamodb-crud-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      }]
    })
  }

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_app" "app" {
  name       = "amplify-app-${var.stack_name}"
  repository = var.github_repo

  build_spec = <<-EOT
    version: 0.1
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
    EOT

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id         = aws_amplify_app.app.id
  branch_name    = "master"
  enable_auto_build = true

  tags = {
    Name        = "amplify-master-branch-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_accessanalyzer_analyzer" "example" {
  analyzer_name = "example"
  type          = "ACCOUNT"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.app_user_pool.id
  description = "The ID of the Cognito User Pool"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_stage.prod_stage.invoke_url
  description = "The URL of the API Gateway stage"
}

output "amplify_app_id" {
  value       = aws_amplify_app.app.id
  description = "The ID of the Amplify app"
}
