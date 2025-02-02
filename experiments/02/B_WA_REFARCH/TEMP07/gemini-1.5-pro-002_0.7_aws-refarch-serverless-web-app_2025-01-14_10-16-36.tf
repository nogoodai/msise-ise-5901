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

variable "github_repo_url" {
  type    = string
  default = "your-github-repo-url" # Replace with your GitHub repository URL
}

variable "github_branch" {
  type    = string
  default = "main"
}


resource "aws_cognito_user_pool" "this" {
  name = "${var.stack_name}-user-pool"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}-${random_id.this.hex}"
  user_pool_id = aws_cognito_user_pool.this.id
}


resource "aws_cognito_user_pool_client" "this" {
  name = "${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.this.id
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls = ["http://localhost:3000/"] # Placeholder, update as needed

}

resource "random_id" "this" {
  byte_length = 8
}

resource "aws_dynamodb_table" "this" {

  name         = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
  read_capacity = 5
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

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-api-gateway-cloudwatch-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

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


# Placeholder resources for API Gateway, Lambda, Amplify, and IAM roles for Lambda and Amplify.  These would need further refinement based on specific function requirements, deployment process and security best practices.

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.this.name
}


