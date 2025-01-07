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
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name                = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id         = aws_cognito_user_pool.main.id
  generate_secret      = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls        = ["http://localhost:3000/"] # Placeholder URL, update as needed
  logout_urls          = ["http://localhost:3000/"] # Placeholder URL, update as needed
  supported_identity_providers = ["COGNITO"]

}



resource "aws_dynamodb_table" "main" {
 name = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5
 server_side_encryption {
   enabled = true
 }
 attribute {
   name = "cognito-username"
   type = "S"
 }
 hash_key = "cognito-username"

 attribute {
   name = "id"
   type = "S"
 }
 range_key = "id"


 tags = {
   Name = "todo-table-${var.stack_name}"
   Environment = "prod" # Set environment
 }
}


resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Effect": "Allow",
   "Principal": {
    "Service": "apigateway.amazonaws.com"
   },
   "Action": "sts:AssumeRole"
  }
 ]
}
EOF
}

resource "aws_iam_role_policy" "api_gateway_cw_policy" {
 name = "api-gateway-cw-policy-${var.stack_name}"
 role = aws_iam_role.api_gateway_cw_role.id

 policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Effect": "Allow",
   "Action": [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
   ],
   "Resource": "*"
  }
 ]
}
EOF
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
}



resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
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
  baseDirectory: /build
  files:
   - '**/*'
EOF


}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true

}



# Placeholder Resources.  These would require substantially more detail to be complete, but are included as placeholders
# to represent a more complete application

resource "aws_iam_role" "lambda_exec_role" {
 name = "lambda_exec_role-${var.stack_name}"
 assume_role_policy = jsonencode({
   Version = "2012-10-17"
   Statement = [
     {
       Action = "sts:AssumeRole"
       Effect = "Allow"
       Principal = {
         Service = "lambda.amazonaws.com"
       }
     },
   ]
 })
}


resource "aws_lambda_function" "example" {
  # ... (Lambda function configuration - Add Item, Get Item, etc.)
}


resource "aws_api_gateway_integration" "example" {
 # ... (API Gateway integration with Lambda functions)
}



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
 value = aws_api_gateway_rest_api.main.id
}



