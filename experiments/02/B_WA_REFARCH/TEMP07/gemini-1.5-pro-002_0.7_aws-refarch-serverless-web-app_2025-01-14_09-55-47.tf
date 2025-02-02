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
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  generate_secret                    = false
  callback_urls                      = ["http://localhost:3000/"] # Placeholder, update with actual callback URL
  logout_urls                        = ["http://localhost:3000/"] # Placeholder, update with actual logout URL
  prevent_user_existence_errors    = "ENABLED" # Prevent duplicate user creation errors
  supported_identity_providers       = ["COGNITO"]

}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_id.main.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "random_id" "main" {
  byte_length = 8
}


# DynamoDB Table
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


# IAM Role for API Gateway Logging
resource "aws_iam_role" "api_gateway_cloudwatch_logs" {
  name = "${var.stack_name}-api-gateway-cw-logs-role"

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

# IAM Policy for API Gateway Logging

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs" {
 name = "${var.stack_name}-api-gateway-cw-logs-policy"
  role = aws_iam_role.api_gateway_cloudwatch_logs.id

 policy = jsonencode({
    Version = "2012-10-17",
 Statement = [
 {
        Effect = "Allow",
        Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
          "logs:PutLogEvents"
 ],
        Resource = "*"
 }
    ]
 })
}




# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
 name = "${var.stack_name}-lambda-role"
 assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
 }
 Effect = "Allow"
 }
    ]
  })

}




# IAM Policy for Lambda (DynamoDB and CloudWatch)
resource "aws_iam_policy" "lambda_dynamodb" {

 name = "${var.stack_name}-lambda-dynamodb-policy"


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
 "dynamodb:Query",
 "dynamodb:BatchWriteItem",
 "dynamodb:BatchGetItem",
 "dynamodb:DescribeTable"
 ],
 Resource = aws_dynamodb_table.main.arn
      },
 {
 Effect = "Allow",
 Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
 ],
 Resource = "arn:aws:logs:*:*:*"
 },
 {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Resource = "*"
      }
    ]
  })
}



resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
 role       = aws_iam_role.lambda_exec.name
 policy_arn = aws_iam_policy.lambda_dynamodb.arn
}





# Amplify App
resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo
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
 baseDirectory: build
 files:
 - '**/*'
 cache:
 paths:
 - node_modules/**/*
EOF

}


# Amplify Branch (Master)
resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true

}

# Placeholder for Lambda functions - Replace with actual function code
resource "aws_lambda_function" "example" {
  # ... Lambda function configuration, referencing the IAM role and policies
 filename      = "lambda_function.zip" # Replace with the path to your zipped Lambda function code
 function_name = "example_lambda_function"
 role          = aws_iam_role.lambda_exec.arn
 handler       = "index.handler" # Replace with your Lambda function handler
 source_code_hash = filebase64sha256("lambda_function.zip")
 runtime = "nodejs16.x"
 memory_size = 1024
 timeout = 60
 tracing_config {
 mode = "Active"
 }
 environment {
 variables = {
 TABLE_NAME = aws_dynamodb_table.main.name
 }
 }
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

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}
