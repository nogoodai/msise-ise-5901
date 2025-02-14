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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The application's name."
  default     = "todo-app"
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token with repo access."
  sensitive   = true
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

 mfa_configuration = "OFF" # Explicit MFA configuration
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev"
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name                                = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                       = aws_cognito_user_pool.main.id
  generate_secret                     = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                 = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  # Use variable for callback and logout URLs
  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls
}

variable "callback_urls" {
  type        = list(string)
  description = "List of callback URLs for the Cognito User Pool Client."
  default     = ["http://localhost:3000/"]
}

variable "logout_urls" {
  type        = list(string)
  description = "List of logout URLs for the Cognito User Pool Client."
  default     = ["http://localhost:3000/"]
}


resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode = "PAY_PER_REQUEST"
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
 point_in_time_recovery {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}



resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"
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

  tags = {
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"
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



# Lambda Functions and related resources

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"

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
 tags = {
    Name        = "lambda-role-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
 }
}


resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda-dynamodb-policy-${var.stack_name}"
 policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDynamoDBAccess",
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
      "Resource": "*"
    }
  ]
}
EOF

 tags = {
    Name        = "lambda-dynamodb-policy-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
 }
}

resource "aws_iam_policy_attachment" "lambda_dynamodb_attachment" {
  name       = "lambda-dynamodb-attachment-${var.stack_name}"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



#  (Placeholders for Lambda function definitions - replace with actual code)

# Example Lambda function resource



resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url
  access_token = var.github_access_token
  build_spec = <<YAML
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
YAML
}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}

# Outputs

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}


output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}


output "amplify_app_id" {
 value = aws_amplify_app.main.id
 description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
 description = "The default domain of the Amplify app."
}


resource "aws_accessanalyzer_analyzer" "example" {
  name = "example"
  type = "ACCOUNT"

 tags = {
    Name = "example"
 }
}

