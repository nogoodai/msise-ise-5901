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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The name of the application."
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository to use."
  default     = "master"
}

variable "github_token" {
  type        = string
  description = "GitHub personal access token."
  sensitive   = true
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  mfa_configuration = "OFF" # Consider enabling MFA for enhanced security

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code"]
  allowed_oauth_scopes                = ["email", "openid"]

  callback_urls = ["http://localhost:3000/"] # Placeholder, replace with actual callback URLs
  logout_urls   = ["http://localhost:3000/"] # Placeholder, replace with actual logout URLs

  prevent_user_existence_errors = "ENABLED"


}

resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PAY_PER_REQUEST" # Use on-demand billing for cost optimization
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

  point_in_time_recovery {
    enabled = true
  }
  tags = {
    Name = "todo-table-${var.stack_name}"
        Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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
    Name = "api-gateway-cloudwatch-role-${var.stack_name}"
        Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Effect   = "Allow",
        Resource = "*" # Restrict resource access. Avoid using *.
      },
    ]
  })
}



resource "aws_apigatewayv2_api" "main" {
 name = "serverless-todo-api-${var.stack_name}"
 protocol_type = "HTTP"

 tags = {
    Name = "serverless-todo-api-${var.stack_name}"
        Environment = "prod"
    Project     = var.application_name
 }
}

resource "aws_accessanalyzer_analyzer" "analyzer" {
  analyzer_name = "access-analyzer-${var.stack_name}"
  type          = "ACCOUNT"
  tags = {
    Name = "access-analyzer-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo
  access_token = var.github_token

  build_spec = <<-EOT
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
EOT

}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}



output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_id" {
  value       = aws_apigatewayv2_api.main.id
  description = "The ID of the API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
 description = "The default domain of the Amplify app."
}

