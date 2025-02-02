terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"
  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"
  password_policy {
    minimum_length                   = 6
    require_lowercase                = true
    require_numbers                 = false
    require_symbols                 = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                 = true
    name                     = "email"
    required                 = true
  }
  username_attributes = ["email"]

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                                 = "${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls                          = ["http://localhost:3000/"] # Replace with your logout URLs
  prevent_user_existence_errors       = "ENABLED"
  supported_identity_providers         = ["COGNITO"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = var.stack_name
  }

}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_string.domain_suffix.result}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_string" "domain_suffix" {
  length  = 8
  special = false
  upper   = false
}


resource "aws_dynamodb_table" "main" {
 name = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 read_capacity = 5
 write_capacity = 5
 hash_key = "cognito-username"
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
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-api-gateway-cloudwatch-role"

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
    Name        = "${var.stack_name}-api-gateway-cloudwatch-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id
 policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
 Action = [
          "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
 })
}

# Placeholder for API Gateway and Lambda resources.
# These resources require more complex configuration based on your specific API definition and Lambda function code.
# You will need to replace these placeholders with the actual implementation for your application.




resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo_url
 platform = "WEB"
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
  cache:
    paths:
      - node_modules/**/*
EOF

  tags = {
    Name        = var.stack_name
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
 stage = "PRODUCTION"

  tags = {
    Name        = "${var.stack_name}-master-branch"
    Environment = "prod"
    Project     = var.stack_name
  }
}



output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}

