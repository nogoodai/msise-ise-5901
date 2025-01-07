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
  default = "us-west-2"
}

variable "project_name" {
  type = string
}

variable "stack_name" {
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
  name = "user-pool-${var.stack_name}"

  username_attributes      = ["email"]
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
  name = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_mode = true
  allowed_oauth_flows          = ["authorization_code", "implicit"]
  allowed_oauth_scopes         = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls        = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls         = ["http://localhost:3000/"] # Placeholder, update as needed
  supported_identity_providers = ["COGNITO"]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name = "todo-table-${var.stack_name}"

  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }

  key {
    name = "cognito-username"
    type = "HASH"
  }
  key {
    name = "id"
    type = "RANGE"
  }


  server_side_encryption {
    enabled = true
  }
  billing_mode = "PROVISIONED"
  read_capacity = 5
  write_capacity = 5
}


# IAM Role for API Gateway logging to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
 name = "api-gateway-cloudwatch-logs-role-${var.stack_name}"
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
      },
    ]
  })
}


# IAM Policy for API Gateway logging to CloudWatch
resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
  name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs_role.id
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
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ],
 Resource = "*"
      },
    ]
  })
}


# Amplify App
resource "aws_amplify_app" "main" {
  name       = "amplify-app-${var.stack_name}"
  repository = var.github_repo_url
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
  environment:
    REACT_APP_REGION: ${var.region}
EOF

}

# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

}





output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_arn" {
 value = aws_dynamodb_table.todo_table.arn
}


output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}


