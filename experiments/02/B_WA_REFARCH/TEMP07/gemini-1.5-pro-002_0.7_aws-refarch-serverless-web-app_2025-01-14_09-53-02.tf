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
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Placeholder, update with your actual callback URLs
  logout_urls          = ["http://localhost:3000/"] # Placeholder, update with your actual logout URLs
  prevent_user_existence_errors = "ENABLED"
  generate_secret                = false
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

# IAM Policy for Lambda functions to access DynamoDB and CloudWatch
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
          "dynamodb:BatchWriteItem",
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
 {
        Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
 ],
 Effect = "Allow",
 Resource = "*"
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Effect = "Allow",
 Resource = "*"
      }
    ]
  })
}

# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Placeholder for Lambda functions - replace with your actual Lambda function code
resource "aws_lambda_function" "example_lambda" {
  filename         = "lambda_function.zip" # Replace with your zipped code
  function_name    = "example_lambda_${var.stack_name}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler" # Replace with your handler
  source_code_hash = filebase64sha256("lambda_function.zip") # Replace with your zipped code
  runtime = "nodejs12.x" # Replace with your runtime
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
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your actual GitHub PAT

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
EOF

}

# Amplify Branch - master branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true


 stage = "PRODUCTION"
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
