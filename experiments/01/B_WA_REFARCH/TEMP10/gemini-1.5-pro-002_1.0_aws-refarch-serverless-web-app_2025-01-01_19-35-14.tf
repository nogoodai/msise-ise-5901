terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
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
  default = "master"
}


provider "aws" {
  region = var.region
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]

  verification_message_template {
    default_email_options {
      email_message = "Your verification code is {####}"
      email_subject = "Welcome to ${var.stack_name}!"
    }
  }

 email_configuration {
    source_arn = "arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:identity/no-reply@${var.stack_name}.com" # Replace with your verified SES identity or remove email configuration
 }
  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows          = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes        = ["email", "phone", "openid"]

  generate_secret = false
  refresh_token_validity = 30 # days

  prevent_user_existence_errors = "ENABLED"
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.stack_name}-auth-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}



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

  tags = {
    Name        = "todo-table"
    Environment = "production"
    Project     = var.stack_name
  }
}

data "aws_caller_identity" "current" {}

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
 name = "api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
        Effect = "Allow",
 Resource = "*"
      }
    ]
  })


}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"

 endpoint_configuration {
    types = ["REGIONAL"]
  }
}




resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  rest_api_id    = aws_api_gateway_rest_api.main.id
  provider_arns   = [aws_cognito_user_pool.main.arn]
}


resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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
}




resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"

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
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
 ],
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
 role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



resource "aws_lambda_function" "add_item_lambda" {
  function_name = "${var.stack_name}-add-item"
  filename      = "add_item.zip" # Replace with your Lambda function zip file
  handler       = "index.handler" # Replace with your Lambda function handler
  role          = aws_iam_role.lambda_role.arn
 runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60
 tracing_config {
    mode = "Active"
 }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

}



resource "aws_amplify_app" "main" {
 name = "${var.stack_name}-amplify-app"
 repository = var.github_repo
 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token.

 build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
 commands:
        - npm run build
  artifacts:
    baseDirectory: /build # Update according to your project
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
  value = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


