terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

variable "region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources in."
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack."
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The application's name, used for resource naming."
}

variable "github_repo_url" {
  type        = string
  description = "URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  default     = "master"
  description = "Branch of the GitHub repository to use for Amplify."
}

variable "tags" {
  type        = map(string)
  default = {
    Environment = "Default",
    Project     = "Default"
  }
  description = "Additional tags for resources."
}

provider "aws" {
  region = var.region
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  mfa_configuration = "OFF" # Explicitly disabling MFA. Consider enabling for better security.

  tags = var.tags
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name                         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                = aws_cognito_user_pool.main.id
  generate_secret              = false
  allowed_oauth_flows          = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes          = ["email", "phone", "openid"]
  callback_urls                = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls                 = ["http://localhost:3000/"] # Placeholder, update as needed
  supported_identity_providers = ["COGNITO"]
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
 read_capacity = 5
 write_capacity = 5
 server_side_encryption {
   enabled = true
 }


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

 point_in_time_recovery {
  enabled = true
 }
 tags = var.tags
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"

  minimum_compression_size = 0 # Setting a valid compression size
 tags = var.tags
}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url
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
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  tags = var.tags
}

resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true

}


resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })
 tags = var.tags
}


resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs" {
 role       = aws_iam_role.api_gateway_role.name
 policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
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
 value       = aws_api_gateway_rest_api.main.id
 description = "The ID of the API Gateway."
}

output "amplify_app_id" {
 value       = aws_amplify_app.main.id
 description = "The ID of the Amplify App."
}

