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
  description = "The AWS region to deploy in."
  default     = "us-east-1"
}

variable "application_name" {
  type        = string
  description = "The name of the application."
  default     = "todo-app"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "dev"
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

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }


  mfa_configuration = "OFF" # Consider enforcing MFA for production


  auto_verified_attributes = ["email"]
  username_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.main.id
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code"] # Removed implicit flow
  allowed_oauth_scopes                = ["email", "phone", "openid", "profile"] # Added profile scope

  # Replace with HTTPS callback and logout URLs for production
  callback_urls        = ["http://localhost:3000/"]
  logout_urls          = ["http://localhost:3000/"]
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }

}

resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PAY_PER_REQUEST" # Changed to on-demand billing
  # Removed read and write capacity as it's not needed for PAY_PER_REQUEST

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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cw-role"

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
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-cw-role"
    Environment = var.stack_name
 Project = var.application_name
  }
}



resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cw-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id


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
 Resource = aws_cloudwatch_log_group.api_gw.arn
      }
    ]
  })
}


resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
  retention_in_days = 30
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"
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

  access_control_configuration {
    # Enforce HTTPS for production
  }
}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true


  # backend_environment_arn = aws_amplify_backend_environment.main.arn # Enable backend environments when needed
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
 value = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.main.id
  description = "The ID of the API Gateway."
}


output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
  value       = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}


