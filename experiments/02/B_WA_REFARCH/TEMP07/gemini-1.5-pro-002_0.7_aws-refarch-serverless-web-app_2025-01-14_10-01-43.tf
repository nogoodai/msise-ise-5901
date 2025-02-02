terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider aws {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project" {
  type    = string
  default = "todo-app"
}

variable "stack_name" {
  type    = string
  default = "todo-app-stack"
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
  name = "${var.project}-user-pool-${var.environment}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
 minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project}-${var.stack_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.project}-user-pool-client-${var.environment}"

 user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls = ["http://localhost:3000/"] # Placeholder, replace with actual URL
  logout_urls   = ["http://localhost:3000/"] # Placeholder, replace with actual URL

  prevent_user_existence_errors = "ENABLED"
}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
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
}


# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-lambda-role-${var.environment}"

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
      }
    ]
  })
}


# IAM Policy for Lambda (DynamoDB and CloudWatch)
resource "aws_iam_policy" "lambda_policy" {
 name = "${var.project}-lambda-policy-${var.environment}"


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
          "dynamodb:BatchWriteItem",
          "dynamodb:BatchGetItem"
        ],
        Resource = aws_dynamodb_table.main.arn,
 Effect = "Allow",
      },
      {
        Action = [
 "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*",
        Effect = "Allow",
      }
    ]
  })
}



# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# Placeholder Lambda Function (Replace with actual Lambda function code)
resource "aws_lambda_function" "example_function" {
  function_name = "${var.project}-example-function-${var.environment}"
  handler       = "index.handler" # Replace with your handler
  role          = aws_iam_role.lambda_role.arn
  runtime = "nodejs16.x" # Update if using different runtime
  memory_size = 1024
  timeout = 60

  # Replace with your Lambda function code
  filename         = "lambda_function.zip" # Example filename
  source_code_hash = filebase64sha256("lambda_function.zip") # Example


  tracing_config {
    mode = "Active"
  }
}


# API Gateway Rest API
resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.project}-api-${var.environment}"
 description = "API Gateway for ${var.project}"

}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {

  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

  depends_on = [
 # Add dependencies here as needed
  ]

  lifecycle {
    create_before_destroy = true
  }
}


# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.project}-amplify-app-${var.environment}"
  repository = var.github_repo_url
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token
}



# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}


# IAM Role for API Gateway CloudWatch Logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.project}-apigw-cw-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
 Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}


# IAM Policy for API Gateway CloudWatch Logging
resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.project}-apigw-cw-policy-${var.environment}"

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

# Attach Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}

# API Gateway Account Settings for CloudWatch Logging
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
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

