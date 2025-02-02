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
  type = string
}

variable "application_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Placeholder, replace with actual callback URLs
  logout_urls                         = ["http://localhost:3000/"] # Placeholder, replace with actual logout URLs


  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


# IAM Role for API Gateway CloudWatch Logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cw-role"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-cw-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Policy for API Gateway CloudWatch Logging
resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cw-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id


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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


# IAM Policy for Lambda (DynamoDB and CloudWatch)
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.application_name}-${var.stack_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

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
 "dynamodb:BatchGetItem",
 "dynamodb:BatchWriteItem"
        ],
 Resource = aws_dynamodb_table.main.arn
      },
 {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
 "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })
}

# Placeholder for Lambda functions - replace with actual Lambda function code
resource "aws_lambda_function" "example_lambda" {
  filename      = "lambda_function.zip" # Replace with your Lambda zip file
  function_name = "${var.application_name}-${var.stack_name}-example-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler" # Replace with your Lambda handler
  source_code_hash = filebase64sha256("lambda_function.zip")
 runtime = "nodejs12.x" # Replace with your desired runtime

 memory_size = 1024
 timeout = 60
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-example-lambda"
 Environment = var.stack_name
    Project     = var.application_name
  }
}



# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with an appropriate method for managing secrets


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
    baseDirectory: /
    files:
      - '**/*'
EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
 Project     = var.application_name
  }
}

# Amplify Branch - master branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
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

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.main.domain
}
