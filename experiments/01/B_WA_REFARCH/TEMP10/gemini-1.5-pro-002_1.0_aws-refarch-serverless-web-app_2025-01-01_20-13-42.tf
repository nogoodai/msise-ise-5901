terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
  generate_secret                   = false
  explicit_auth_flows               = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  allowed_oauth_flows               = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes              = ["email", "phone", "openid"]
  callback_urls                     = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls                       = ["http://localhost:3000/"] # Replace with your logout URLs

  # prevent_user_existence_errors = "ENABLED"
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



resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.application_name}-${var.stack_name}-api"
 description = "API Gateway for ${var.application_name}"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  provider_arns   = [aws_cognito_user_pool.main.arn]
}



resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-role"

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
 name = "${var.application_name}-${var.stack_name}-lambda-dynamodb-policy"

 policy = jsonencode({
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
     "Resource": aws_dynamodb_table.main.arn
    },
    {
     "Sid": "CloudWatchLogsPolicy",
      "Effect": "Allow",
      "Action": [
       "logs:CreateLogGroup",
       "logs:CreateLogStream",
       "logs:PutLogEvents"
     ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchMetricsPolicy",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "xray:PutTraceSegments",
      "Resource": "*"
    }

   ]
 })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}




resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url

 access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with an actual personal access token
 custom_rules = [
 {
 source = "/<*>"
 target = "/index.html"
 status = "200"
 }
 ]

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
  artifacts:
   baseDirectory: /build
   files:
    - '**/*'
  cache:
   paths:
    - node_modules/**/*

EOF
}



resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 stage       = "PRODUCTION"
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

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}


output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}

