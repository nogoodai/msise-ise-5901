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
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
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

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                      = ["http://localhost:3000/"] # Replace with your callback URL
  logout_urls                       = ["http://localhost:3000/"] # Replace with your logout URL
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
 server_side_encryption {
    enabled = true
  }

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

 tags = {
    Name = "todo-table-${var.stack_name}"
  }
}




# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role_${var.stack_name}"

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
}

# IAM Policy for Lambda to access DynamoDB
resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "lambda_dynamodb_policy_${var.stack_name}"
 policy = jsonencode({
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
 "dynamodb:Scan"
 ],
 "Resource": aws_dynamodb_table.main.arn
      },
 {
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:*:*:*",
        "Effect": "Allow"
      },
      {
        "Effect": "Allow",
 "Action": [
          "xray:PutTraceSegments",
 "xray:PutTelemetryRecords"
 ],
        "Resource": "*"
 }
 ]
  })
}

# Attach DynamoDB policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# Placeholder for Lambda functions (replace with your actual Lambda code)


# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
 repository = var.github_repo
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token

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
    baseDirectory: /
    files:
      - '**/*'
  environment:
    REACT_APP_API_URL: $API_GATEWAY_ENDPOINT # This will be replaced dynamically
YAML
}

# Amplify Branch (master)
resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.main.id
  branch_name = "master"

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


