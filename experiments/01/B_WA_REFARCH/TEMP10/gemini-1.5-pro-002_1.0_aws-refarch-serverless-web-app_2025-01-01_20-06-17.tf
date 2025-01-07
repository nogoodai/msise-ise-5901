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

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}


variable "github_repo_url" {
  type = string
  description = "URL of the GitHub repository for the Amplify app"
}

variable "github_repo_branch" {
 type = string
 default = "master"
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
}


resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                        = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Placeholder, update with actual callback URL
  logout_urls = ["http://localhost:3000/"] # Placeholder, update with actual logout URL
  supported_identity_providers       = ["COGNITO"]
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

# Placeholder for API Gateway and Lambda resources
# These will be complex and require more detailed definitions
# based on the specific API and Lambda function requirements

resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}"
 repository = var.github_repo_url
 access_token = var.github_access_token # Requires manual creation, should be stored securely

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
         - mv build dist
 artifacts:
   baseDirectory: /dist
   files:
     - '**/*'
EOF

}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true

  # Placeholder basic build settings. Enhance as required
  # Add environment variables, build commands and more
  # based on project needs.
  #  backend_environment_arn = aws_elastic_beanstalk_environment.main.environment_arn
}


# Placeholder for IAM Roles and Policies
# Define detailed roles and policies for
# API Gateway, Amplify, and Lambda functions.



# Placeholder Outputs - replace with actual resource IDs, ARNs, and URLs
output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

variable "github_access_token" {}

