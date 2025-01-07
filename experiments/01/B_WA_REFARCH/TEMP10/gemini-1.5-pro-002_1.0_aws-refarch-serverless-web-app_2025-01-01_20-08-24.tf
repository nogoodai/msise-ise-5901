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
  type    = string
  default = "us-west-2"
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

variable "github_access_token" {
  type = string
  sensitive = true
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

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls   = ["http://localhost:3000/"] # Placeholder, update as needed
}

resource "aws_dynamodb_table" "main" {
 name         = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
 read_capacity = 5
 write_capacity = 5
 hash_key      = "cognito-username"
 range_key     = "id"
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


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Action": "sts:AssumeRole",
   "Principal": {
    "Service": "apigateway.amazonaws.com"
   },
   "Effect": "Allow",
   "Sid": ""
  }
 ]
}
EOF
}

resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
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


resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}

resource "aws_apigatewayv2_api" "main" {

 name = "${var.application_name}-api-${var.stack_name}"
 protocol_type = "HTTP"

}



resource "aws_amplify_app" "main" {
 name = "${var.application_name}-${var.stack_name}"
 repository = var.github_repo_url
 access_token = var.github_access_token
 build_spec = <<EOF
version: 1
frontend:
 phases:
  preBuild:
   commands:
    - npm ci
  build:
   commands:
    - npm run build
 artifacts:
  baseDirectory: build
  files:
   - '**/*'
EOF
}



resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
  enable_auto_build = true
}



output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "cognito_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}


output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
  value = aws_apigatewayv2_api.main.id
}



output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}
