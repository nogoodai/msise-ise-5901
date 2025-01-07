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

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
 type = string
 default = "todo-app"
}

variable "github_repo_url" {
 type = string
}

variable "github_repo_branch" {
 type = string
 default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

 email_verification_message = "Your verification code is {####}"
 email_verification_subject = "Verify your email address"

  verification_message_template {
    default_email_options {
      sms_verification_message = "Your verification code is {####}"
    }
  }

  auto_verified_attributes = ["email"]
 tags = {
    Name = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

 allowed_oauth_flows_user_agent = true
  allowed_oauth_flows            = ["code", "implicit"]
  allowed_oauth_scopes          = ["phone", "email", "openid"]
  callback_urls                 = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls                  = ["http://localhost:3000/"] # Replace with your logout URLs

  generate_secret = false
  prevent_user_existence_errors = "ENABLED"
  refresh_token_validity = 30

  supported_identity_providers = ["COGNITO"]
}


resource "aws_dynamodb_table" "todo_table" {
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
    Name = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
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
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
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




output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}


