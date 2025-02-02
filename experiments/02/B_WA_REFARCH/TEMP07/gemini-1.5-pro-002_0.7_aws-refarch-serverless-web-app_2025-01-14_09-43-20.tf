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
  default = "main"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"

  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_agent = true
  allowed_oauth_flows            = ["code", "implicit"]
  allowed_oauth_scopes          = ["email", "phone", "openid"]

  callback_urls      = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls        = ["http://localhost:3000/"] # Replace with your logout URLs
  prevent_user_existence_check = false
  generate_secret               = false # Security best practice
 refresh_token_validity = 30
}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
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

 tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
  }
}


# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role_${var.stack_name}"

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


# IAM Policy for Lambda function to access DynamoDB
resource "aws_iam_policy" "lambda_policy" {
 name = "lambda_policy_${var.stack_name}"

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
        "Resource": [
 aws_dynamodb_table.main.arn
 ]
      },
      {
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        "Resource": "*",
        "Effect": "Allow"
      }
    ]
  })
}


# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# Lambda Function (Example - Add Item)
resource "aws_lambda_function" "add_item_lambda" {
  function_name = "add_item_lambda_${var.stack_name}"
  filename      = "add_item_lambda.zip" # Replace with your function's zip file
  source_code_hash = filebase64sha256("add_item_lambda.zip")
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler" # Replace with your function's handler
 runtime      = "nodejs12.x"
  memory_size = 1024
 timeout      = 60

  tracing_config {
    mode = "Active"
  }
}

# Placeholder for other Lambda functions (Get, Update, Delete, etc.)
# ... Similar configuration as add_item_lambda but with different filenames, handlers, etc. ...


# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
}

# API Gateway Authorizer (Cognito)
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name               = "cognito_authorizer"
  rest_api_id       = aws_api_gateway_rest_api.main.id
  type               = "COGNITO_USER_POOLS"
  provider_arns      = [aws_cognito_user_pool.main.arn]
}




# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo_url
}


# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}
