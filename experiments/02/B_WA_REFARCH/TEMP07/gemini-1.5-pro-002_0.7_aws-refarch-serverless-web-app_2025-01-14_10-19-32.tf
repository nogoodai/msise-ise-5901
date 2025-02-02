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

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}




resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name                         = "${var.stack_name}-client"
  user_pool_id                = aws_cognito_user_pool.main.id
  generate_secret              = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows          = ["authorization_code", "implicit"]
  allowed_oauth_scopes        = ["email", "phone", "openid"]
  callback_urls                = ["http://localhost:3000/"] # Placeholder, replace with your actual callback URL
  logout_urls                 = ["http://localhost:3000/"] # Placeholder, replace with your actual logout URL

}

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


resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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
}


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "${var.stack_name}-api-gateway-cw-policy"
  role = aws_iam_role.api_gateway_role.id

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
      },
    ]
  })
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
}



resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo
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
   cache:
     paths:
       - node_modules/**/*
 EOF
}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

}



# Placeholder resources for Lambda functions and related IAM roles/policies
# These will need to be fleshed out based on the specific requirements of the CRUD operations



