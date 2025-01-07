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


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes = ["email"]
  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_PASSWORD_AUTH"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false


}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo_table" {
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
    Name        = "todo-table-${var.stack_name}"
 Environment = var.stack_name
 Project     = var.application_name
  }

}

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-${var.stack_name}"

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
      }
    ]
  })

}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name} application"

}



resource "aws_iam_role" "lambda_dynamodb_role" {
  name = "lambda-dynamodb-${var.stack_name}"
 assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })
}


resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "lambda-dynamodb-policy-${var.stack_name}"
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
          "dynamodb:BatchGetItem",
 "dynamodb:BatchWriteItem",
 "dynamodb:Scan",
 "dynamodb:Query"


        ],
        Resource = aws_dynamodb_table.todo_table.arn
      },
 {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },

      {
 Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData"
 ],
 Resource = "*"
 }
    ]
 })

}



resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_dynamodb_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url

  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with a GitHub Personal Access Token

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
}




resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true
}


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


