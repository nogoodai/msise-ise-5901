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
  default = "us-east-1"
}

variable "stack_name" {
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_token" {
  type = string
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

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-client"

  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  
  callback_urls = ["http://localhost:3000"]
  logout_urls  = ["http://localhost:3000"]

  allowed_oauth_flows_user_pool_client = true
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name = "${var.stack_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "main" {
  name          = "CognitoUserPoolAuthorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
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

# Lambda IAM Role
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

# Lambda Policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.stack_name}-lambda-policy"
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
      },
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
  for_each = toset(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"])

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
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-${each.key}"
    Environment = "production"
  }
}

# API Gateway Role
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
resource "aws_iam_role_policy" "api_gateway_cloudwatch" {
  name = "${var.stack_name}-api-gateway-cloudwatch"
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

# Amplify App
resource "aws_amplify_app" "main" {
  name = var.stack_name
  repository = var.github_repo
  access_token = var.github_token

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

  custom_rule {
    source = "/<*>"
    status = "404-200"
    target = "/index.html"
  }
}

# Amplify Branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"

  framework = "React"
  stage     = "PRODUCTION"

  enable_auto_build = true
}

# Amplify Role
resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
}

# Amplify Policy
resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "amplify:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_rest_api.main,
    aws_api_gateway_authorizer.main
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "api_gateway_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}"
}

output "amplify_app_url" {
  value = "https://${aws_amplify_branch.master.branch_name}.${aws_amplify_app.main.default_domain}"
}
