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
  type        = string
  description = "The AWS region to deploy the resources into."
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack. Used for naming resources."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The name of the application. Used for naming resources."
  default     = "todo-app"
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}


variable "github_access_token" {
  type        = string
  description = "GitHub personal access token with appropriate permissions for Amplify."
  sensitive   = true
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
 mfa_configuration = "OFF" # Explicitly set MFA to OFF. Consider enabling MFA for production.


  schema {
    name     = "email"
    attribute_data_type = "String"
    mutable  = false
    required = true
  }

  schema {
 name = "phone_number"
 attribute_data_type = "String"
 mutable = true
 }
  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "dev" # Replace with your environment
    Project     = "todo-app"
  }

}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"

  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
  callback_urls = ["http://localhost:3000/"] # Placeholder, replace with actual callback URL
  logout_urls = ["http://localhost:3000/"]   # Placeholder, replace with actual logout URL

}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
 server_side_encryption {
    enabled = true
  }
  hash_key = "cognito-username"
  range_key = "id"

 point_in_time_recovery {
 enabled = false # Explicitly set PITR to false.  Consider enabling for production.
 }

  attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "dev" # Replace with your environment
    Project     = "todo-app"
  }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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
    Name        = "api-gateway-cloudwatch-role-${var.stack_name}"
    Environment = "dev" # Replace with your environment
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Resource = "*" # Consider restricting this to specific log groups.
      },
    ]
  })
}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo_url

  access_token = var.github_access_token

 build_spec = <<EOF
version: 0.1
phases:
  install:
    commands:
      - npm install
  build:
    commands:
      - npm build
artifacts:
  baseDirectory: /
  files:
    - '**/*'
EOF

}

resource "aws_amplify_branch" "main" {
 app_id   = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
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

output "amplify_app_id" {
 value = aws_amplify_app.main.id
 description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
  value       = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}


