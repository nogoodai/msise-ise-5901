terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

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
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
 read_capacity = 5
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
 Environment = var.stack_name
 Project     = var.application_name
  }
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo
  build_spec = <<EOF
version: 0.1
frontend:
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
 Environment = var.stack_name
    Project     = var.application_name
  }
}



resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cloudwatch-role"

 assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-cloudwatch-role"
 Environment = var.stack_name
    Project     = var.application_name
  }
}