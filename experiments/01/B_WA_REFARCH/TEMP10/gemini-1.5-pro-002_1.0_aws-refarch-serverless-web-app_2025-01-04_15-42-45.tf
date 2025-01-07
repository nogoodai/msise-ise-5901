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

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "stack_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows_user_pool_client = true
 allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.project_name}-${var.environment}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "todo_table" {
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
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-role"

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
  name = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-cw-policy"
  role = aws_iam_role.api_gateway_role.id
  policy = jsonencode({
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
  })
}



resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-${var.environment}-${var.stack_name}-api"
  protocol_type = "HTTP"
}


resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-role"
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


resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-dynamodb-policy"
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
 "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
 "dynamodb:Scan",
 "dynamodb:Query"
 ],
        Resource = aws_dynamodb_table.todo_table.arn
      },
    ]
  })
}


resource "aws_iam_policy_attachment" "lambda_dynamodb_attachment" {
  name       = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-dynamodb-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-cloudwatch-policy"

  policy = jsonencode({
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
 })
}

resource "aws_iam_policy_attachment" "lambda_cloudwatch_attachment" {
  name       = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-cloudwatch-attachment"
 roles      = [aws_iam_role.lambda_role.name]
 policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}



resource "aws_amplify_app" "main" {
  name       = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with a secure method to manage secrets
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
 baseDirectory: build
    files:
 - '**/*'
EOF
}



resource "aws_amplify_branch" "master" {
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
  value = aws_dynamodb_table.todo_table.name
}


output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


output "api_gateway_url" {
 value = aws_apigatewayv2_api.main.api_endpoint
}
