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

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}

variable "domain_prefix" {
  type = string
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes = ["email"]

  tags = {
    Name = "${var.stack_name}-cognito-user-pool"
    Environment = "prod"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name            = "${var.stack_name}-user-pool-client"
  user_pool_id    = aws_cognito_user_pool.main.id
  generate_secret = false


  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls = ["http://localhost:3000/"] # Placeholder, replace with your frontend URL

  tags = {
    Name = "${var.stack_name}-cognito-user-pool-client"
    Environment = "prod"
  }
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

 tags = {
   Name = "${var.stack_name}-dynamodb-table"
   Environment = "prod"
 }
}

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-api-gateway-cloudwatch-role"

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

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

 policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
 Resource = "*"
 }
    ]
  })
}



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  tags = {
    Name = "${var.stack_name}-api-gateway"
    Environment = "prod"
  }

}


resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo_url
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with an appropriate method for retrieving the token

  build_spec = <<-EOT
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
  cache:
    paths:
      - node_modules/**/*

EOT

 tags = {
    Name = "${var.stack_name}-amplify-app"
    Environment = "prod"
  }

}

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

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}


