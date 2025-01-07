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
  default = "serverless-todo-app"
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
  default = "master"
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes      = ["email"]
 auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  explicit_auth_flows                = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  generate_secret                    = false
  supported_identity_providers       = ["COGNITO"]
 callback_urls                      = ["http://localhost:3000/"] # Replace with your frontend URL
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  prevent_user_existence_errors = "ENABLED"


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

 server_side_encryption {
    enabled = true
  }


}


# IAM Role for API Gateway logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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



# IAM Policy for API Gateway logging
resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
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
      },
    ]
  })
}

# API Gateway (Example - needs expansion with methods and integrations)
resource "aws_apigatewayv2_api" "main" {
 name = "serverless-todo-api-${var.stack_name}"
 protocol_type = "HTTP"
}


# Lambda Functions (Placeholders - you need to define each function and its configuration)


# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub PAT
 custom_rules = [
 {
      source = "/<*>/"
      target = "/index.html"
      status = 200
    },

  ]


}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  stage       = "PRODUCTION"
 enable_auto_build = true

}



# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })

}


# IAM Policy for Amplify (This is a basic example and might need adjustments based on your specific needs)
resource "aws_iam_role_policy" "amplify_policy" {
 name = "amplify-policy-${var.stack_name}"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = "*",
 Resource = "*"
      }
    ]

  })
}


# Outputs


