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

variable "environment" {
  default = "prod" 
}

variable "github_repo_url" {
  description = "GitHub repository URL for Amplify"
}

variable "github_access_token" {
  description = "GitHub personal access token"
  sensitive   = true
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verify_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Environment = var.environment
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
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

# Cognito Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB Table
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

  tags = {
    Environment = var.environment
    Project     = var.stack_name
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
    stage  = "prod"
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
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Functions
locals {
  lambda_functions = {
    add_item = {
      handler = "index.addItem"
      http_method = "POST"
      path = "/item"
    }
    get_item = {
      handler = "index.getItem"
      http_method = "GET"
      path = "/item/{id}"
    }
    get_all_items = {
      handler = "index.getAllItems"
      http_method = "GET"
      path = "/item"
    }
    update_item = {
      handler = "index.updateItem"
      http_method = "PUT"
      path = "/item/{id}"
    }
    complete_item = {
      handler = "index.completeItem"
      http_method = "POST"
      path = "/item/{id}/done"
    }
    delete_item = {
      handler = "index.deleteItem"
      http_method = "DELETE"
      path = "/item/{id}"
    }
  }
}

resource "aws_lambda_function" "todo_functions" {
  for_each = local.lambda_functions

  filename         = "lambda.zip"
  function_name    = "${var.stack_name}-${each.key}"
  role            = aws_iam_role.lambda_role.arn
  handler         = each.value.handler
  runtime         = "nodejs12.x"

  memory_size = 1024
  timeout     = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.stack_name
  }
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name = "${var.stack_name}-amplify"
  repository = var.github_repo_url
  access_token = var.github_access_token

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

  enable_auto_branch_creation = true
  enable_branch_auto_build = true
}

# Amplify Branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"

  framework = "React"
  stage     = "PRODUCTION"

  enable_auto_build = true
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

resource "aws_iam_role_policy_attachment" "api_gateway_logs" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
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

resource "aws_iam_role_policy_attachment" "amplify_admin" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "api_gateway_url" {
  value = "${aws_api_gateway_rest_api.todo_api.execution_arn}/prod"
}

output "amplify_app_url" {
  value = "https://${aws_amplify_branch.master.branch_name}.${aws_amplify_app.todo_app.default_domain}"
}
