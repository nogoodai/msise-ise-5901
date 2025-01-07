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

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "serverless-todo"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.environment}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]


  tags = {
    Environment = var.environment
    Project     = var.project_name
    Name        = "${var.application_name}-user-pool"

  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.environment}-${var.project_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {

  name = "${var.application_name}-client"

  user_pool_id = aws_cognito_user_pool.main.id


  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]


  generate_secret = false
}



resource "aws_dynamodb_table" "todo_table" {
 name           = "todo-table-${var.environment}"
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
    Environment = var.environment
    Project     = var.project_name
    Name        = "todo-table"
  }

}

# API Gateway and Lambda functions (Placeholders - Implementation depends on specific API requirements)


resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.application_name}-api"
 description = "API Gateway for ${var.application_name}"
}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-app"
  repository = var.github_repo
  platform   = "WEB"
  build_spec = <<YAML
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
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
YAML


  tags = {
    Environment = var.environment
    Project     = var.project_name
    Name        = "${var.application_name}-amplify-app"

  }

}

resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true
}

# IAM roles and policies
resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "${var.application_name}-api-gateway-cw-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
  ]
 })

 tags = {
    Environment = var.environment
    Project     = var.project_name
    Name        = "${var.application_name}-api-gateway-cw-logs-role"

  }
}


resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs_policy" {
 policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
 role       = aws_iam_role.api_gateway_cloudwatch_logs_role.name
}

output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}
output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}
output "dynamodb_table_arn" {
 value = aws_dynamodb_table.todo_table.arn
}
output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}
output "amplify_app_id" {
 value = aws_amplify_app.main.id
}
output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.main.domain
}

