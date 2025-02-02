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

variable "stack_name" {
  type = string
}

variable "application_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                 = true
    name                     = "email"
    required                 = true

  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
}


resource "aws_dynamodb_table" "todo_table" {
 name         = "todo-table-${var.stack_name}"
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

 tags = {
   Name = "todo-table-${var.stack_name}"
   Environment = var.stack_name
   Project = var.application_name
 }
}

resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"

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


resource "aws_iam_role_policy" "api_gateway_cw_policy" {
 name = "api-gateway-cw-policy-${var.stack_name}"
 role = aws_iam_role.api_gateway_cw_role.id

 policy = jsonencode({
   Version = "2012-10-17",
   Statement = [
     {
       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents"
       ],
       Resource = "*",
       Effect = "Allow"
     }
   ]
 })
}

resource "aws_apigatewayv2_api" "api" {
 name = "serverless-api-${var.stack_name}"
 protocol_type = "HTTP"
}


resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {

  name = "lambda-dynamodb-policy-${var.stack_name}"
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
          "dynamodb:Scan",
          "dynamodb:DescribeTable"
        ],
        Resource = aws_dynamodb_table.todo_table.arn,
        Effect = "Allow"
      }
    ]
 })
}


resource "aws_iam_policy_attachment" "lambda_dynamodb_attachment" {
 name       = "lambda-dynamodb-attachment-${var.stack_name}"
 roles      = [aws_iam_role.lambda_exec_role.name]
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_policy" "lambda_cw_policy" {
 name = "lambda-cloudwatch-policy-${var.stack_name}"
 policy = jsonencode({
   Version = "2012-10-17",
   Statement = [
     {
       Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "cloudwatch:PutMetricData"
       ],
       Resource = "*",
       Effect   = "Allow",
     }
   ]
 })
}


resource "aws_iam_policy_attachment" "lambda_cw_attachment" {
 name = "lambda-cloudwatch-attachment-${var.stack_name}"
 roles = [aws_iam_role.lambda_exec_role.name]
 policy_arn = aws_iam_policy.lambda_cw_policy.arn
}


resource "aws_amplify_app" "app" {
 name = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub PAT
 build_spec = <<-EOT
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
   baseDirectory: /
   files:
     - '**/*'
 EOT

}


resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.app.id
 branch_name = var.github_repo_branch
 enable_auto_build = true
}


output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.pool.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
 value = aws_apigatewayv2_api.api.id
}


output "amplify_app_id" {
 value = aws_amplify_app.app.id
}


output "amplify_default_domain" {
  value = aws_amplify_app.app.default_domain
}
