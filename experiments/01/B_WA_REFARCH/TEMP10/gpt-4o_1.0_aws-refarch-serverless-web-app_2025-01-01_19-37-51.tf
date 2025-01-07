terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack for naming resources"
  type        = string
  default     = "myapp-stack"
}

locals {
  cognito_user_pool_name      = "cognito-user-pool-${var.stack_name}"
  cognito_user_pool_client_id = "cognito-user-pool-client-${var.stack_name}"
  dynamodb_table_name         = "todo-table-${var.stack_name}"
  custom_domain_name          = "auth.${var.stack_name}.example.com"
  amplify_app_name            = "amplify-app-${var.stack_name}"
}

// Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                   = local.cognito_user_pool_name
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers  = false
    require_symbols  = false
  }

  tags = {
    Name        = local.cognito_user_pool_name
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name            = local.cognito_user_pool_client_id
  user_pool_id    = aws_cognito_user_pool.user_pool.id
  generate_secret = false
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "openid", "phone"]

  tags = {
    Name        = local.cognito_user_pool_client_id
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = local.custom_domain_name
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

// DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name         = local.dynamodb_table_name
  billing_mode = "PROVISIONED"
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

  tags = {
    Name        = local.dynamodb_table_name
    Environment = "production"
    Project     = var.stack_name
  }
}

// API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "api-gateway-${var.stack_name}"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_resource" "api_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

// Placeholder for Lambda functions and integrations
// ... (similar configurations for POST, GET, PUT, DELETE)

// Amplify App
resource "aws_amplify_app" "amplify_app" {
  name       = local.amplify_app_name
  repository = "https://github.com/example/repo-name"

  build_spec = <<EOF
version: 1
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
    KEY = "value"
  }

  tags = {
    Name        = local.amplify_app_name
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id    = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_autobuild = true

  tags = {
    Name        = "amplify-branch-master-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

// IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name = "api-gateway-policy-${var.stack_name}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_api_gateway_policy" {
  policy_arn = aws_iam_policy.api_gateway_policy.arn
  role       = aws_iam_role.api_gateway_role.name
}

// Additional IAM roles and policies for Amplify and Lambda
// ...

// Outputs
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}
