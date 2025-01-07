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
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  generate_secret                    = false
  callback_urls                      = ["http://localhost:3000/"] # Placeholder URL, update with your frontend URL
  logout_urls                       = ["http://localhost:3000/"] # Placeholder URL, update with your frontend URL
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
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
  name = "${var.application_name}-${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })
}


# IAM Policy for Lambda to access DynamoDB
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
 "dynamodb:Scan",

        ],
        Resource = aws_dynamodb_table.main.arn,
        Effect = "Allow",
      },
    ],
 })
}

# Attach the DynamoDB policy to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# IAM Policy for Lambda to publish CloudWatch metrics
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
 Resource = "arn:aws:logs:*:*:*",
 Effect   = "Allow"
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*",
 Effect = "Allow"
      },
    ]
  })
}

# Attach the CloudWatch policy to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}


# Lambda functions (Placeholder - replace with actual Lambda function code)


# API Gateway (Placeholder - Requires detailed API definition and integration with Lambda functions)

# Amplify App (Placeholder - Requires GitHub repository URL and build settings)


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}


