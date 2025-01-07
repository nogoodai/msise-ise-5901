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
  default = "serverless-todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
  default = "https://github.com/your-github-username/your-repo-name" # Replace with your GitHub repository URL
}

variable "github_repo_branch" {
  type = string
  default = "main"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id        = aws_cognito_user_pool.main.id
  generate_secret      = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
 allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls        = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls         = ["http://localhost:3000/"] # Replace with your logout URLs

  supported_identity_providers = ["COGNITO"]
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


# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role_${var.stack_name}"

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

# IAM Policy for Lambda to access DynamoDB and CloudWatch
resource "aws_iam_policy" "lambda_policy" {

  name = "lambda_policy_${var.stack_name}"

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
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
 "dynamodb:BatchWriteItem"
        ],
        Effect   = "Allow",
 Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
 "cloudwatch:PutMetricData"
 ],
        Effect   = "Allow",
 Resource = "*"
 }
    ]
 })
}

# Attach policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_policy.arn
}


# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.application_name}-api-${var.stack_name}"
 description = "API Gateway for ${var.application_name}"
}


# Placeholder for Lambda functions (replace with your actual function code and configuration)
# Example Lambda function (you'll need to create one for each CRUD operation)



# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your Github Access Token
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
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOT
  iam_service_role_arn = aws_iam_role.amplify_role.arn
}




# Amplify Branch (connects to the master branch of the GitHub repo)

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  stage       = "PRODUCTION" # or "BETA", "DEVELOPMENT", etc.
 enable_auto_build = true

}


# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name = "amplify_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
 Effect = "Allow",
 Principal = {
          Service = "amplify.amazonaws.com"
 }
      },
    ]
  })
}


# IAM Policy for Amplify
resource "aws_iam_policy" "amplify_policy" {
  name = "amplify_policy_${var.stack_name}"
 policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
 {
 Effect = "Allow",
 Action = "*", # Replace with more specific permissions as needed
 Resource = "*" # Replace with more specific resources as needed
 }
    ]
 })
}


# Attach policy to Amplify role
resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
 role       = aws_iam_role.amplify_role.name
 policy_arn = aws_iam_policy.amplify_policy.arn
}


# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
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

output "amplify_app_default_domain" {
  value = aws_amplify_app.main.default_domain
}



