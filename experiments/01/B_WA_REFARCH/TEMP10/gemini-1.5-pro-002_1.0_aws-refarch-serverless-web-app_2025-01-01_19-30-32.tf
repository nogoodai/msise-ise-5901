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
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers = false
    require_symbols = false
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name               = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.main.id
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH"]
  generate_secret     = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                      = ["http://localhost:3000/"] # Replace with your actual callback URLs
  logout_urls                         = ["http://localhost:3000/"] # Replace with your actual logout URLs
}


resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.stack_name}-${random_id.main.hex}"
 user_pool_id = aws_cognito_user_pool.main.id
}


resource "random_id" "main" {
  byte_length = 8
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
 attribute {
    name = "cognito-username"
    type = "S"
  }
 attribute {
    name = "id"
    type = "S"
 }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-api-gateway-cloudwatch-role"

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


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

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
 name        = "${var.stack_name}-api"
 description = "API Gateway for ${var.stack_name}"
}


resource "aws_amplify_app" "main" {
  name       = var.stack_name
 repository = var.github_repo
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token or store securely in secrets management


 build_spec = <<YAML
version: 0.1
frontend:
 phases:
   install:
     commands:
       - npm install
   build:
     commands:
       - npm run build
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
YAML
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
 enable_auto_build = true

}


resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
 name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:BatchGetItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": "${aws_dynamodb_table.main.arn}"
    }
  ]
}
EOF
}




# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}


output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}


