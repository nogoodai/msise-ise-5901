terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the infrastructure in."
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack."
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application."
}

variable "github_repo_owner" {
  type        = string
  description = "The owner of the GitHub repository."
}

variable "github_repo_name" {
  type        = string
  description = "The name of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  default     = "master"
  description = "The branch of the GitHub repository to deploy."
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
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


# IAM Role for API Gateway Logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"
  assume_policy = jsonencode({
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
resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:EnableLogGroupFields",
          "logs:GetLogGroupFields",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
        ],
        Resource = "*"
      },
    ]
  })
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"

  assume_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow"
      }]
  })
}


# IAM Policy for Lambda to access DynamoDB and CloudWatch
resource "aws_iam_policy" "lambda_policy" {
 name = "lambda-policy-${var.stack_name}"
 policy = jsonencode({
  Version = "2012-10-17",
  Statement = [
   {
    Effect = "Allow",
    Action = [
     "dynamodb:BatchGetItem",
     "dynamodb:GetItem",
     "dynamodb:Query",
     "dynamodb:Scan",
     "dynamodb:BatchWriteItem",
     "dynamodb:PutItem",
     "dynamodb:UpdateItem",
     "dynamodb:DeleteItem"
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
        "cloudwatch:PutMetricData"
    ],
    Resource = "*"
    }
  ]
 })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
 policy_arn = aws_iam_policy.lambda_policy.arn
 role       = aws_iam_role.lambda_role.name
}



# Placeholder for Lambda functions (replace with actual Lambda function code)
resource "aws_lambda_function" "add_item_function" {
 filename      = "add_item_function.zip" # Replace with your function code
 function_name = "add-item-function-${var.stack_name}"
 handler       = "index.handler" # Replace with your handler
 runtime       = "nodejs12.x"
 role          = aws_iam_role.lambda_role.arn
 memory_size   = 1024
 timeout       = 60
 tracing_config {
   mode = "Active"
 }
 # Add environment variables, layers, etc. as needed
}

# ... (Similarly define other Lambda functions: get_item, get_all_items, update_item, complete_item, delete_item)


# Amplify App
resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = "https://github.com/${var.github_repo_owner}/${var.github_repo_name}"
 access_token = var.github_personal_access_token # Use a secure way to manage this token
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
     postBuild:
       commands:
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
 EOT
}

variable "github_personal_access_token" {
  type = string
  description = "GitHub personal access token with appropriate permissions for the repository."
  sensitive = true
}

resource "aws_s3_bucket" "main" {
 bucket = "${var.application_name}-s3-bucket-${var.stack_name}"
 acl    = "private"
}

# Amplify Branch
resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true
}


# API Gateway (Simplified example - expand as needed)
resource "aws_apigatewayv2_api" "main" {
  name = "${var.application_name}-api-${var.stack_name}"
  protocol_type = "HTTP"
}

# ... (Add API Gateway routes, integrations with Lambda functions, authorizer configuration, stages, and usage plans)


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

output "api_gateway_url" {
  value = aws_apigatewayv2_api.main.api_endpoint # Replace with the actual API Gateway endpoint URL
}
