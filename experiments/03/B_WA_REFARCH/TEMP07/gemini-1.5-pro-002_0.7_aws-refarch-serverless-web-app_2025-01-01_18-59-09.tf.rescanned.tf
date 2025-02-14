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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "serverless-todo-app"
}

variable "application_name" {
  type        = string
  description = "The application Name"
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The GitHub repository URL."
}

variable "github_branch" {
  type        = string
  description = "The GitHub branch to deploy from"
  default     = "master"
}

variable "github_access_token" {
  type        = string
  description = "GitHub Personal Access Token (PAT)"
  sensitive   = true
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
  mfa_configuration = "OFF" # CIS Benchmark 4.9 - MFA should be enforced

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "default"
    Project     = var.application_name
  }

}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = "default"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Replace with actual callback URLs
  logout_urls          = ["http://localhost:3000/"] # Replace with actual logout URLs
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "default"
    Project     = var.application_name
  }
}



resource "aws_dynamodb_table" "main" {
 name         = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
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

 point_in_time_recovery {
  enabled = true # Enable point-in-time recovery
 }

 tags = {
   Name        = "todo-table-${var.stack_name}"
   Environment = "default"
   Project     = var.application_name
 }

}


resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"

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

 tags = {
   Name        = "api-gateway-cw-role-${var.stack_name}"
   Environment = "default"
   Project     = var.application_name
 }
}


resource "aws_iam_role_policy" "api_gateway_cw_policy" {
 name = "api-gateway-cw-policy-${var.stack_name}"
 role = aws_iam_role.api_gateway_cw_role.id

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
       Resource = "*" # Should be more restrictive according to OWASP recommendations
     }
   ]
 })

 tags = {
   Name        = "api-gateway-cw-policy-${var.stack_name}"
   Environment = "default"
   Project     = var.application_name
 }
}



resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.application_name}-api-${var.stack_name}"
 description = "API Gateway for ${var.application_name}"

 minimum_compression_size = 0

 tags = {
   Name        = "${var.application_name}-api-${var.stack_name}"
   Environment = "default"
   Project     = var.application_name
 }
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo
  access_token = var.github_access_token



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
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "default"
    Project     = var.application_name
  }
}



resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-amplify-branch-${var.stack_name}"
    Environment = "default"
    Project     = var.application_name
  }
}


# Outputs

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



