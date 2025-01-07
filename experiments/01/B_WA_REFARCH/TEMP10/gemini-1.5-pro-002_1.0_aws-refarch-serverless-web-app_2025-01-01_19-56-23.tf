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

  username_attributes = ["email"]

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }
}


resource "aws_cognito_user_pool_client" "client" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls        = ["http://localhost:3000/"] # Update with your callback URL
  logout_urls         = ["http://localhost:3000/"] # Update with your logout URL
  supported_identity_providers = ["COGNITO"]


}

resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
  read_capacity  = 5
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



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"
}


resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  rest_api_id     = aws_api_gateway_rest_api.main.id
 provider_arns  = [aws_cognito_user_pool.main.arn]
}



resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.application_name}-${var.stack_name}-apigw-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "demo" {

 cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn

}




resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token with appropriate permissions
 build_spec = <<-EOT
version: 0.1
frontend:
 phases:
  install:
    commands:
      - npm install
  preBuild:
    commands:
     - npm run build
  build:
    commands:
      - npm run export
 artifacts:
  baseDirectory: /out
  files:
      - '**/*'
 cache:
  paths:
      - node_modules/**/*
EOT
}

resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.main.id
  branch_name         = var.github_repo_branch
  enable_auto_build = true

}



resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-role"

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
  name = "${var.application_name}-${var.stack_name}-lambda-dynamodb-policy"

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
 "dynamodb:GetItem",
          "dynamodb:PutItem",
 "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:Query",
 "dynamodb:Scan"
        ],
        Effect   = "Allow",
 Resource = aws_dynamodb_table.todo_table.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name = "${var.application_name}-${var.stack_name}-lambda-cloudwatch-policy"
 policy = jsonencode({
 Version = "2012-10-17",
 Statement = [
 {
 Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
 ],
 Effect = "Allow",
 Resource = "arn:aws:logs:*:*:*"
 }
 ]
 })

}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_attachment" {
 role = aws_iam_role.lambda_execution_role.name
 policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
 value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}
