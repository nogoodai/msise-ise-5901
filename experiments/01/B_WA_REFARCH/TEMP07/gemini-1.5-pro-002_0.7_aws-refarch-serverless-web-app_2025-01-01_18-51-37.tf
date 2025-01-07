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
}

variable "github_repo_branch" {
  type    = string
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



resource "aws_amplify_app" "main" {
 name             = "${var.application_name}-${var.stack_name}-amplify-app"
 repository       = var.github_repo_url
 access_token     = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token
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

resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-bucket"
}



# Placeholder for Lambda functions and other resources.  This section needs to be filled in based on the specific logic of the TODO application.
# Due to the complexity and length limitations, implementing the full Lambda function code, API Gateway integration, IAM policies, and other details within this single .tf file is not feasible.
# The user will need to add those specific configurations based on their TODO application logic.



output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
 #  value = aws_api_gateway_deployment.main.invoke_url
 value = "REPLACE_WITH_API_GATEWAY_URL" # Placeholder, replace with actual API Gateway URL after deployment.
}


