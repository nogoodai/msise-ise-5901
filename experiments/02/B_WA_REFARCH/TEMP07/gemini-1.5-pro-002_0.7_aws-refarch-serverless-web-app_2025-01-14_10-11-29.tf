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
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
 email_configuration {
    source_arn = aws_ses_email_identity.example.arn
  }
}

resource "aws_ses_email_identity" "example" {
 email_address = "user@example.com"
}




resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
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
}



resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"

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
}

resource "aws_iam_role_policy" "api_gateway_cw_policy" {
 name = "api-gateway-cw-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
}



resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = "https://github.com/example/repo"

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
    baseDirectory: /
    files:
      - '**/*'
EOF
}




resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
  enable_auto_build = true
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
  value = aws_amplify_app.main.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.main.domain
}
