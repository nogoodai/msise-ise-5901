terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
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


provider "aws" {
  region = var.aws_region
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  username_attributes = ["email"]

  verification_message_template {
    default_email_options {
      email_message = "Your verification code is {####}"
      email_subject = "Welcome to ${var.stack_name}"
    }
  }

  auto_verified_attributes = ["email"]
}



resource "aws_cognito_user_pool_client" "main" {
  name                         = "${var.stack_name}-user-pool-client"
  user_pool_id                 = aws_cognito_user_pool.main.id
  generate_secret               = false
  explicit_auth_flows          = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
  allowed_oauth_flows          = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes          = ["email", "phone", "openid"]
  callback_urls                 = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls                  = ["http://localhost:3000/"] # Replace with your logout URLs
  prevent_user_existence_errors = "ENABLED"

}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_string.main.result}"
  user_pool_id = aws_cognito_user_pool.main.id
}



resource "random_string" "main" {
  length  = 8
  special = false
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
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
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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


resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs" {
  name = "${var.stack_name}-api-gateway-cloudwatch-logs-policy"
  role = aws_iam_role.api_gateway_role.id

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
 name = "${var.stack_name}-api"
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

resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "${var.stack_name}-lambda-dynamodb-policy"
 policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:BatchGetItem",
        "dynamodb:Scan"


      ],
      "Resource": aws_dynamodb_table.main.arn
    }
  ]
}

EOF

}

resource "aws_iam_policy_attachment" "lambda_dynamodb_policy_attachment" {
 name       = "${var.stack_name}-lambda-dynamodb-attach"
 roles      = [aws_iam_role.lambda_role.name]
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
 name = "${var.stack_name}-lambda-cloudwatch-policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}



resource "aws_iam_policy_attachment" "lambda_cloudwatch_policy_attachment" {
 name = "${var.stack_name}-lambda-cloudwatch-attach"
 roles = [aws_iam_role.lambda_role.name]
 policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}




resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token
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
  baseDirectory: build
  files:
   - '**/*'
YAML

}

resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true
}


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

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}
