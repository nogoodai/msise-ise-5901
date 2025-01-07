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
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type    = string
  default = "your-github-repo" # Replace with your GitHub repository URL
}

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name                = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.main.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000"] # Replace with your callback URLs
  logout_urls          = ["http://localhost:3000"] # Replace with your logout URLs
  supported_identity_providers = ["COGNITO"]
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key = {
    name = "cognito-username"
    type = "S"
  }
 range_key = {
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


# (API Gateway, Lambda functions, Amplify, IAM Roles and Policies require more detailed implementation based on function code and build process. These placeholders illustrate the structure and necessary resources.)


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}



resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cloudwatch-role"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-cloudwatch-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo
  access_token = "your-github-access-token" # Replace with your GitHub Access Token. Consider storing in AWS Secrets Manager

  build_settings {
    platform = "WEB"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
  branch_name   = var.github_branch
  enable_auto_build = true
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

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}
