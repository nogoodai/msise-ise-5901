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

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"
  username_attributes = ["email"]

  password_policy {
    minimum_length                   = 6
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                 = false
    require_symbols                 = false
    temporary_password_validity_days = 7
  }

 email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email for ${var.stack_name}"

  sms_verification_message = "Your verification code is {####}"

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.stack_name}-${random_id.main.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}



resource "random_id" "main" {
  byte_length = 2
}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                      = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls                        = ["http://localhost:3000/"] # Placeholder, update as needed
  supported_identity_providers       = ["COGNITO"]
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "cognito-username"
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
    Environment = "production" # Update as needed
  }

}



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




resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}




resource "aws_api_gateway_rest_api" "main" {

  name        = "todo-api-${var.stack_name}"

}


resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id  = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}


resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role-${var.stack_name}"

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

resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "lambda-dynamodb-policy-${var.stack_name}"
  policy = jsonencode({
 Version = "2012-10-17",
    Statement = [

      {
        Action = [
 "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
 "dynamodb:Scan"
 ],

        Effect   = "Allow",
 Resource = aws_dynamodb_table.main.arn
      },


    ]
 })
}



resource "aws_iam_policy_attachment" "lambda_dynamodb_attachment" {
  name       = "lambda-dynamodb-attachment-${var.stack_name}"
  roles      = [aws_iam_role.lambda_execution_role.name]
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}





resource "aws_lambda_function" "add_item_function" {
  function_name = "add-item-function-${var.stack_name}"
  filename      = "add_item.zip" # Placeholder, update with your function code
  handler       = "index.handler" # Placeholder, update with your handler
 runtime = "nodejs12.x"

 role = aws_iam_role.lambda_execution_role.arn
  memory_size = 1024
  timeout     = 60


}



resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" #Replace with actual personal access token or use secrets manager


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
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*

EOF
}



resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}


