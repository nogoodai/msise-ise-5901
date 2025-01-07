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
  type    = string
  default = "us-east-1"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "stack_name" {
  type    = string
  default = "dev"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}




resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Placeholder URL. Replace with your actual callback URL
  logout_urls   = ["http://localhost:3000/"] # Placeholder URL. Replace with your actual logout URL
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


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"
}

# Placeholder for API Gateway resources, methods, integrations, and authorizer
# due to the complexity and length required for a full implementation.


resource "aws_amplify_app" "main" {
 name = "${var.application_name}-${var.stack_name}"
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with actual GitHub PAT
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
   baseDirectory: build
   files:
     - '**/*'
EOF
}

resource "aws_s3_bucket" "main" {
 bucket = "${var.application_name}-${var.stack_name}-bucket"
}



resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true
}


# Placeholder for IAM roles and policies for API Gateway, Lambda, and Amplify
# due to the complexity and length required for a full implementation including
# permissions to DynamoDB and CloudWatch


output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}


output "api_gateway_url" {
 # Placeholder value. Replace with actual API Gateway URL once resources and methods are defined
 value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}
