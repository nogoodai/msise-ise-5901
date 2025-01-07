terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "stack_name" {
  default = "my-app"
}

variable "cognito_user_pool_name" {
  default = "user-pool"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.cognito_user_pool_name}-${var.stack_name}"

  auto_verified_attributes = ["email"]
  
  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.cognito_user_pool_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id
  
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
  supported_identity_providers = ["COGNITO"]

  callback_urls = ["https://your-app-url"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"

  hash_key       = "cognito-username"
  range_key      = "id"

  read_capacity  = 5
  write_capacity = 5

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
  name        = "my-api-gateway"
  description = "API for to-do app"

  endpoint_configuration {
    types = ["EDGE"]
  }
  
  provider = aws
  
  binary_media_types = ["application/octet-stream"]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.api.id
  deployment_id        = aws_api_gateway_deployment.deploy.id
  description          = "Production stage"
  tags = {
    Name = "api-stage-prod"
  }

  access_log_settings {
    destination_arn = "${aws_cloudwatch_log_group.api_gateway.arn}:log-group"
    format          = "$context.identity.sourceIp - $context.identity.caller [$context.requestTime] $context.method $context.resourcePath $context.protocol $context.resourceId $context.status $context.requestTimeEpoch $context.responseLatency"
  }

  xray_tracing_enabled = true
}

resource "aws_lambda_function" "crud_ops" {
  for_each    = { "addItem" = "POST /item", "getItem" = "GET /item/{id}", "getAllItems" = "GET /item", "updateItem" = "PUT /item/{id}", "completeItem" = "POST /item/{id}/done", "deleteItem" = "DELETE /item/{id}" }
  function_name = "crud-${each.key}-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  
  memory_size = 1024
  timeout     = 60
  
  role = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo.name
    }
  }
  
  tracing_config {
    mode = "Active"
  }

  code {
    s3_bucket = "my-lambda-functions"
    s3_key    = "path/to/my/lambda/${each.key}.zip"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-execution-role"

  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy.json
}

data "aws_iam_policy_document" "ecs_assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_amplify_app" "frontend" {
  name              = "frontend-app"
  repository        = "https://github.com/user/repo"
  
  build_spec = <<EOF
    version: 0.1
    frontend:
      phases:
        build:
          commands:
            - npm install
            - npm run build
      artifacts:
        baseDirectory: /build
        files:
          - '**/*'
    cache:
      paths:
        - node_modules/**/*
  EOF
  
  environment_variables = {
    AWS_REGION = var.region
  }

  providers = [aws]
}

resource "aws_amplify_branch" "main" {
  app_id           = aws_amplify_app.frontend.id
  branch_name      = "master"
  enable_auto_build = true
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "amplify_app_endpoint" {
  value = aws_amplify_app.frontend.default_domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}
