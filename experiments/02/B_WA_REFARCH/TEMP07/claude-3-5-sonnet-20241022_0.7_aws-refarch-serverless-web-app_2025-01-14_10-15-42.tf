terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS Region"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack"
  default     = "todo-app"
}

variable "github_repo" {
  description = "GitHub repository URL"
  type        = string
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verify_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_symbols   = false
    require_numbers   = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable            = true
    required           = true

    string_attribute_constraints {
      min_length = 3
      max_length = 256
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  
  allowed_oauth_flows  = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  
  callback_urls = ["https://${aws_amplify_app.frontend.default_domain}/callback"]
  logout_urls   = ["https://${aws_amplify_app.frontend.default_domain}/signout"]

  allowed_oauth_flows_user_pool_client = true
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.stack_name
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name = "${var.stack_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "CognitoUserPoolAuthorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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

# Lambda DynamoDB Policy
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

# Lambda CloudWatch Policy
resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.stack_name}-lambda-cloudwatch-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Functions
resource "aws_lambda_function" "crud_functions" {
  for_each = {
    add_item     = "POST"
    get_item     = "GET"
    get_all      = "GET"
    update_item  = "PUT"
    complete     = "POST"
    delete_item  = "DELETE"
  }

  filename         = "lambda/${each.key}.zip"
  function_name    = "${var.stack_name}-${each.key}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs12.x"
  memory_size     = 1024
  timeout         = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-${each.key}"
    Environment = "production"
  }
}

# Amplify App
resource "aws_amplify_app" "frontend" {
  name         = "${var.stack_name}-frontend"
  repository   = var.github_repo
  
  build_spec = <<-EOT
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
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  enable_branch_auto_build = true

  environment_variables = {
    ENV = "production"
  }
}

# Amplify Branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "master"

  framework = "React"
  stage     = "PRODUCTION"

  enable_auto_build = true
}

# API Gateway IAM Role
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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
}

# API Gateway CloudWatch Policy
resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_role.id

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

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_url" {
  value = "https://${aws_amplify_app.frontend.default_domain}"
}
