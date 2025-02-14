terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
  description = "The AWS region to deploy the resources in."
}

variable "stack_name" {
  type = string
  description = "The name of the stack."
}

variable "application_name" {
  type = string
 description = "The application's name"
}

variable "github_repo" {
  type = string
 description = "The URL of the application's repository"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes = ["email"]

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
    temporary_password_validity_days = 7

  }

  mfa_configuration = "OFF"

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }

}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]


  generate_secret = false

  callback_urls = ["https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com/oauth2/idpresponse"]
  logout_urls   = ["https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com/logout"]

  prevent_user_existence_errors = "ENABLED"



  supported_identity_providers = ["COGNITO"]


}

resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST"
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
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
 minimum_compression_size = 0

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
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /build
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

resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
 branch_name = "master"
 enable_auto_build = true


}

resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.application_name}-${var.stack_name}-access-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name = "${var.application_name}-${var.stack_name}-access-analyzer"
    Environment = var.stack_name
    Project = var.application_name
  }
}



output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "ID of the Cognito User Pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
 description = "The name of the DynamoDB table"
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
 description = "The ID of the API Gateway"
}


