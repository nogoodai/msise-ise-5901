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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-east-1"
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
  description = "GitHub personal access token with repo scope."
  sensitive   = true
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
  mfa_configuration = "OFF" # Consider changing to "ON" for production

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  explicit_auth_flows                = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  generate_secret                    = false
  prevent_user_existence_errors      = "ENABLED"
  callback_urls                      = ["http://localhost:3000/"] # Placeholder, update with actual frontend URL
  logout_urls                       = ["http://localhost:3000/"] # Placeholder, update with actual frontend URL
  supported_identity_providers       = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
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
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
 description = "API Gateway for ${var.application_name}"
 minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = "dev"
    Project     = var.application_name
 }
}


resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-bucket"
  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
      }
    }
  }


  logging {
    target_bucket = "${var.application_name}-${var.stack_name}-bucket-logs" # Replace with an existing log bucket name
 target_prefix = "log/"
  }

 tags = {
    Name        = "${var.application_name}-${var.stack_name}-bucket"
    Environment = "dev"
    Project     = var.application_name
  }
}


resource "aws_s3_bucket" "logs" {
 bucket = "${var.application_name}-${var.stack_name}-bucket-logs"
  acl    = "log-delivery-write"
 force_destroy = true

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-bucket-logs"
    Environment = "dev"
    Project     = var.application_name
  }
}




resource "aws_amplify_app" "main" {
 name             = "${var.application_name}-${var.stack_name}-amplify-app"
 repository       = var.github_repo_url
 access_token     = var.github_access_token
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
     postBuild:
       commands:
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF

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

output "api_gateway_url" {
 value = aws_api_gateway_rest_api.main.id
  description = "The URL of the API Gateway."
}

resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "access-analyzer-${var.stack_name}"
  type          = "ACCOUNT"

  tags = {
    Name = "access-analyzer-${var.stack_name}"
  }
}
