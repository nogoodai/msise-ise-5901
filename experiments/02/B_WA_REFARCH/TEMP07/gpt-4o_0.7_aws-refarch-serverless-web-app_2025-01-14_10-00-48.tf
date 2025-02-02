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
  description = "The AWS region to deploy the resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for naming resources"
  default     = "prod"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify app"
}

variable "github_branch" {
  description = "GitHub branch for Amplify app"
  default     = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "this" {
  user_pool_id = aws_cognito_user_pool.this.id
  name         = "user-pool-client-${var.stack_name}"

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "openid", "phone"]
  supported_identity_providers = ["COGNITO"]

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
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
    read_capacity_units  = 5
    write_capacity_units = 5
  }

  server_side_encryption {
    enabled = true
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "api-${var.stack_name}"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "item_methods" {
  for_each = toset(["GET", "POST", "PUT", "DELETE"])
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.item_resource.id
  http_method   = each.value
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_authorizer" "this" {
  name                     = "cognito-authorizer"
  rest_api_id              = aws_api_gateway_rest_api.this.id
  identity_source          = "method.request.header.Authorization"
  provider_arns            = [aws_cognito_user_pool.this.arn]
  type                     = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = "prod"
  description   = "Production Stage"
  deployment_id = aws_api_gateway_deployment.this.id
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.prod.stage_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.prod.stage_name
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

# Lambda Functions
resource "aws_lambda_function" "crud_functions" {
  for_each = {
    add_item       = "POST /item"
    get_item       = "GET /item/{id}"
    get_all_items  = "GET /item"
    update_item    = "PUT /item/{id}"
    complete_item  = "POST /item/{id}/done"
    delete_item    = "DELETE /item/{id}"
  }
  function_name = "${each.key}-function-${var.stack_name}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role-${var.stack_name}"

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
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  for_each = {
    read_ops  = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
    write_ops = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  }
  policy_arn = each.value
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.lambda_exec.name
}

# Amplify App
resource "aws_amplify_app" "this" {
  name               = "amplify-app-${var.stack_name}"
  repository         = var.github_repo
  oauth_token        = var.github_token

  build_spec = <<EOF
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
        baseDirectory: /
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*

EOF

  auto_branch_creation {
    enabled = true
  }

  auto_branch_creation_config {
    basic_auth_credentials = ""
    build_spec            = aws_amplify_app.this.build_spec
    enable_auto_build     = true
    enable_basic_auth     = false
  }
}

resource "aws_amplify_branch" "master" {
  app_id          = aws_amplify_app.this.id
  branch_name     = var.github_branch
  enable_auto_build = true
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_logs" {
  name = "api-gateway-logs-role-${var.stack_name}"

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
}

resource "aws_iam_role_policy_attachment" "api_gateway_logs_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
  role       = aws_iam_role.api_gateway_logs.name
}

resource "aws_iam_role" "amplify_exec" {
  name = "amplify-exec-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_access_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AWSAmplifyAdminAccess"
  role       = aws_iam_role.amplify_exec.name
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.this.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
