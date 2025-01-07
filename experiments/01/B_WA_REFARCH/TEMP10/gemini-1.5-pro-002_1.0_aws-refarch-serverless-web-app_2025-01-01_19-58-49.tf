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
  name = "${var.application_name}-user-pool-${var.stack_name}"

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
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                     = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
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
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"


  tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
}

resource "aws_api_gateway_usage_plan" "main" {
  name         = "${var.application_name}-usage-plan-${var.stack_name}"
  description  = "Usage plan for ${var.application_name}"
 product_code = "TODO_APP_USAGE_PLAN"

  throttle_settings {
    burst_limit = 100
 rate_limit    = 50
  }

  quota_settings {
 limit  = 5000
    period = "DAY"
  }
}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo
 build_spec = <<EOF
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
EOF

  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true


  tags = {
 Name        = "${var.application_name}-amplify-branch-main-${var.stack_name}"
 Environment = "prod"
    Project     = var.application_name
  }
}




output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}


output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}


output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
 default     = null
}


