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
  type        = string
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Name of the project"
  default     = "todo-project"
}

variable "stack_name" {
  type        = string
  description = "Name of the stack"
  default     = "dev"
}

locals {
  cognito_domain   = "${var.project_name}-${var.stack_name}"
  todo_table_name  = "todo-table-${var.stack_name}"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  mfa_configuration        = "ON"

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.project_name}-${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_AUTH_CODE_FLOW", "ALLOW_IMPLICIT_FLOW"]

  o_auth_flows {
    authorization_code_grant = true
    implicit_code_grant      = true
  }

  allowed_o_auth_scopes = ["email", "phone", "openid"]
  generate_secret       = true
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain       = local.cognito_domain
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = local.todo_table_name
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
    Name        = local.todo_table_name
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-${var.stack_name}-api"
  description = "API for the ${var.project_name}"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  body = <<EOF
{
  "openapi": "3.0.1",
  "info": {
    "title": "${var.project_name} API",
    "version": "1.0"
  },
  "paths": {
    "/item": {
      "get": {},
      "post": {}
    },
    "/item/{id}": {
      "get": {},
      "put": {},
      "delete": {},
      "post": {
        "operationId": "completeItem"
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

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.project_name}-${var.stack_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  description   = "Production stage"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = "$context.identity.sourceIp - $context.identity.caller [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
  }

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api-stage"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name = "/aws/api-gateway/${var.project_name}-${var.stack_name}"

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api-gateway-logs"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
  depends_on  = [aws_api_gateway_integration.lambda_integration]
}

resource "aws_lambda_function" "lambda_functions" {
  for_each = {
    add_item     = "POST /item"
    get_item     = "GET /item/{id}"
    get_all      = "GET /item"
    update_item  = "PUT /item/{id}"
    complete_item = "POST /item/{id}/done"
    delete_item  = "DELETE /item/{id}"
  }

  filename       = "function-code.zip" # This should point to your Lambda zip file.
  function_name  = "${var.project_name}-${each.key}"
  role           = aws_iam_role.lambda_exec_role.arn
  handler        = "index.handler"
  runtime        = "nodejs14.x"
  memory_size    = 1024
  timeout        = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-${each.key}"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.project_name}-${var.stack_name}-amplify-app"

  repository = "https://github.com/your-repo/your-app.git"  # Replace with your GitHub repo

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
EOF

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id     = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "Invoke URL for the API Gateway"
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "amplify_app_id" {
  description = "ID of the Amplify App"
  value       = aws_amplify_app.amplify_app.id
}
