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

variable "github_repo" {
  type    = string
  default = "your-github-repo"
}

variable "github_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
    require_uppercase = true
  }

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  generate_secret = false
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



resource "aws_apigatewayv2_api" "main" {
 name          = "${var.stack_name}-api"
 protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name         = "prod"
 auto_deploy = true
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "COGNITO_USER_POOLS"
  name             = "cognito_authorizer"
  identity_source = ["$request.header.Authorization"]
  provider_arns    = [aws_cognito_user_pool.main.arn]
}


resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.stack_name}-lambda-dynamodb-policy"
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
 "dynamodb:Scan",
 "dynamodb:Query"
 ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
 ],
        Effect = "Allow",
 Resource = "arn:aws:logs:*:*:*"
      },
      {
 Action = [
 "cloudwatch:PutMetricData"
 ],
 Effect = "Allow",
 Resource = "*"
 }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo

 build_spec = <<-EOT
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
 EOT
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
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
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

