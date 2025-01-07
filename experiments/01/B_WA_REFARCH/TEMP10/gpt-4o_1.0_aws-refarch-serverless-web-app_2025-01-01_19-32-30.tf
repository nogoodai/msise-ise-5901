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
  description = "The AWS region to create resources in"
  default     = "us-east-1"
  type        = string
}

variable "stack_name" {
  description = "Unique identifier for this stack"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository URL for the Amplify app"
  type        = string
}

resource "aws_cognito_user_pool" "main" {
  name = "user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "user-pool-client-${var.stack_name}"

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "cognito-username"
  range_key      = "id"

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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_function" "crud_function" {
  function_name = "${var.stack_name}-crud"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-crud"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_method" "items" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_rest_api.main.root_resource_id
  http_method   = "ANY"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_cognito_user_pool.main.id
}

resource "aws_cloudwatch_log_group" "lambda_log" {
  name              = "/aws/lambda/${aws_lambda_function.crud_function.function_name}"
  retention_in_days = 14
}

resource "aws_amplify_app" "frontend" {
  name                = "app-${var.stack_name}"
  repository          = var.github_repo
  oauth_token         = var.github_token
  build_spec          = "amplify.yml"
  
  tags = {
    Name        = "amplify-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "LambdaExecRole-${var.stack_name}"

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
    Name        = "LambdaExecRole-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role" "api_gateway_role" {
  name = "ApiGatewayRole-${var.stack_name}"

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
    Name        = "ApiGatewayRole-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB Table"
  value       = aws_dynamodb_table.todo.name
}

output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_api_gateway_rest_api.main.id
}
