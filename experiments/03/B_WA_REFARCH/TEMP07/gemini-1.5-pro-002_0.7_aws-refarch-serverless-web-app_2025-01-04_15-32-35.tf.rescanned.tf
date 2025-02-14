terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider aws {
  region = var.region
}

variable "region" {
  type        = string
  description = "The AWS region to deploy the resources to."
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
  description = "GitHub personal access token with appropriate permissions."
  sensitive   = true
}



resource "aws_cognito_user_pool" "main" {
  name                    = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length     = 6
    require_lowercase = true
    require_uppercase = true
  }

  mfa_configuration = "OFF" # Consider enforcing MFA for enhanced security

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                             = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                    = aws_cognito_user_pool.main.id
  generate_secret                 = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows              = ["authorization_code", "implicit"]
  allowed_oauth_scopes             = ["email", "phone", "openid"]

  # Use HTTPS for production environments
  callback_urls = ["http://localhost:3000/"] # Replace with your actual callback URLs
  logout_urls   = ["http://localhost:3000/"] # Replace with your actual logout URLs

    tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-domain"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
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

 point_in_time_recovery {
    enabled = true
 }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }

}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo
  access_token = var.github_token


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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-branch"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}



resource "aws_accessanalyzer_analyzer" "analyzer" {
  analyzer_name = "example"
  tags = {
    Name = "example"
 }
 type = "ACCOUNT"
}


output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "cognito_user_pool_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "The domain of the Cognito User Pool."
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
  value = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}

