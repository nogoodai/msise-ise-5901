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
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                        = aws_cognito_user_pool.main.id
  generate_secret                     = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/"] # Placeholder, update with your callback URL
  logout_urls                          = ["http://localhost:3000/"] # Placeholder, update with your logout URL
  supported_identity_providers        = ["COGNITO"]
}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.application_name}-${var.stack_name}"
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
 tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



# IAM Role for API Gateway Logging

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
      }
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




# API Gateway (Placeholder - requires detailed API definition)
#  This is a placeholder and needs to be replaced with the actual API Gateway configuration.

resource "aws_apigatewayv2_api" "main" {
  name          = "serverless-api-${var.stack_name}"
  protocol_type = "HTTP"
}




# Lambda Functions (Placeholder - requires function code and integration with API Gateway)
# This is a placeholder and needs to be fleshed out with actual Lambda function definitions

resource "aws_lambda_function" "example" {
 filename      = "lambda_function_payload.zip" # Replace with your function code
 function_name = "example-${var.stack_name}"
  handler       = "index.handler" # Replace with your handler function
  runtime       = "nodejs16.x"
 memory_size = 1024
 timeout = 60
  role          = aws_iam_role.lambda_exec_role.arn # Define an IAM Role

  tracing_config {
 mode = "Active"
 }

 environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
 }

}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role-${var.stack_name}"

  assume_role_policy = jsonencode({
 Version = "2012-10-17",
 Statement = [
 {
        Action = "sts:AssumeRole",
        Effect = "Allow",
 Principal = {
          Service = "lambda.amazonaws.com"
 }
      }
    ]
 })
}



resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
 policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# Amplify App (Placeholder - requires GitHub repository details and build settings)

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url

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
 baseDirectory: /build
      files:
        - '**/*'
    cache:
 paths:
 - node_modules/**/*

EOF

}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
 stage = "PRODUCTION" # Set to appropriate stage
}




# Outputs
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

output "api_gateway_id" {
  value = aws_apigatewayv2_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}
