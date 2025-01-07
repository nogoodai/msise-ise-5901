terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the application stack."
  type        = string
}

variable "github_repository" {
  description = "The GitHub repository hosting the frontend application."
  type        = string
}

variable "domain_name" {
  description = "Custom domain name for Cognito."
  type        = string
}

resource "aws_cognito_user_pool" "this" {
  name = "cognito-user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length       = 6
    require_uppercase    = true
    require_lowercase    = true
    require_numbers      = false
    require_symbols      = false
  }

  tags = {
    Name        = "cognito-user-pool-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "cognito-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id

  allowed_oauth_flows          = ["code", "implicit"]
  allowed_oauth_scopes         = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  generate_secret = false

  tags = {
    Name        = "cognito-client-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain      = var.domain_name
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_dynamodb_table" "this" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

  attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  hash_key  = "cognito-username"
  range_key = "id"

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "this" {
  name = "api-gateway-${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "item_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_authorizer" "this" {
  name                     = "cognito-authorizer-${var.stack_name}"
  rest_api_id              = aws_api_gateway_rest_api.this.id
  provider_arns            = [aws_cognito_user_pool.this.arn]
  identity_source          = "method.request.header.Authorization"
  type                     = "COGNITO_USER_POOLS"
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
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }

  tags = {
    Name        = "add-item-function-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_amplify_app" "this" {
  name  = "amplify-app-${var.stack_name}"
  repository = var.github_repository

  build_spec = file("buildspec.yml")

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "main" {
  app_id = aws_amplify_app.this.id
  branch_name = "master"

  tags = {
    Name        = "amplify-branch-master-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "api_logging" {
  name = "api-gateway-logging-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "api-logging-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "amplify-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_execution" {
  name = "lambda-execution-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "lambda-execution-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
