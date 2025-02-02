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
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

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
  name               = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id      = aws_cognito_user_pool.main.id
  generate_secret    = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Placeholder - update with actual callback URL
  logout_urls    = ["http://localhost:3000/"] # Placeholder - update with actual logout URL

}


resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  hash_key       = "cognito-username"
  range_key      = "id"
 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5

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
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
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
          "dynamodb:DescribeTable"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
 {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
 Effect = "Allow",
        Resource = "*"
      },
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

# Attach DynamoDB policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


# Placeholder for Lambda function code - replace with your actual code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir = "./lambda" # Replace with path to your Lambda function code
  output_path = "lambda_function.zip"
}



# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your actual GitHub access token

  build_spec = jsonencode({
    version = 0.1,
    frontend = {
      phases = {
        preBuild  = "npm install",
        build     = "npm run build",
        postBuild = "npm run deploy"
      }
      artifacts = {
        baseDirectory = "/dist",
        files = ["**/*"]
      }
      cache = {
        paths = ["node_modules/**/*"]
      }
    }
  })
}


# Amplify Branch (master branch)
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}
