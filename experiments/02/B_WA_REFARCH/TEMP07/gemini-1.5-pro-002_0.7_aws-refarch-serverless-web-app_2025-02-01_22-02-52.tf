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
  name = "${var.stack_name}-user-pool"

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
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.main.id


  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                = ["phone", "email", "openid"]

  callback_urls = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls   = ["http://localhost:3000/"] # Placeholder, update as needed

  generate_secret = false

  prevent_user_existence_errors = "ENABLED"

}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
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

# IAM Role for Lambda
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

# IAM Policy for Lambda (DynamoDB Access)
resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "${var.stack_name}-lambda-dynamodb-policy"
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
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

# IAM Policy Attachment
resource "aws_iam_policy_attachment" "lambda_dynamodb_attachment" {
  name       = "${var.stack_name}-lambda-dynamodb-attachment"
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
  roles      = [aws_iam_role.lambda_role.name]
}

# Placeholder for Lambda functions (replace with your actual Lambda code)
resource "aws_lambda_function" "example_lambda" {
  filename         = "lambda_function.zip" # Replace with your Lambda zip file
  function_name = "${var.stack_name}-example-lambda"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler" # Replace with your handler
  source_code_hash = filebase64sha256("lambda_function.zip")
  runtime = "nodejs16.x" # Update runtime as needed

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



# Amplify App
resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with a secure method to store secrets
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
    baseDirectory: /dist
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
}


# Amplify Branch - Master Branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true

}

# IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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

# IAM Policy for API Gateway (CloudWatch Logs)
resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
 name = "${var.stack_name}-api-gateway-cloudwatch-policy"

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
        Resource = "*"
      }
    ]
  })
}

# IAM Policy Attachment
resource "aws_iam_policy_attachment" "api_gateway_cloudwatch_attachment" {
  name       = "${var.stack_name}-api-gateway-cloudwatch-attachment"
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
  roles      = [aws_iam_role.api_gateway_role.name]
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

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.example_lambda.arn
}
