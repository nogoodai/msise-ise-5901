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

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                = ["phone", "email", "openid"]

  generate_secret = false

  callback_urls        = ["http://localhost:3000/"] # Update with your callback URLs
  logout_urls         = ["http://localhost:3000/"] # Update with your logout URLs
  supported_identity_providers = ["COGNITO"]
}

resource "aws_dynamodb_table" "main" {
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
 Project = var.application_name
  }
}



resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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


resource "aws_iam_role_policy" "api_gateway_policy" {
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


resource "aws_api_gateway_rest_api" "main" {
 name        = "todo-api-${var.stack_name}"
  description = "API Gateway for Todo App"

}

# (Example Resource for Lambda function and integration with API Gateway - repeat for each Lambda function)

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  handler = "index.handler" # Update with your Lambda handler
 runtime = "nodejs12.x"
  memory_size = 1024
 timeout = 60
  role = aws_iam_role.lambda_exec_role.arn
  # ... (Lambda function code and configuration) ...
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "lambda-dynamodb-policy-${var.stack_name}"


 policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem",
                "dynamodb:Query",
                "dynamodb:Scan"
 ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogStream",
            "Resource": "arn:aws:logs:*:*:log-group:/aws/lambda/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF

}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# ... (API Gateway methods, resources, and integrations with Lambda functions) ...


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url
  access_token = "your_github_access_token" # Replace with your GitHub access token


  build_spec = <<YAML
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
YAML
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true

}


# Outputs

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}


output "api_gateway_url" {
 value = aws_api_gateway_deployment.main.invoke_url # Replace with your API Gateway deployment resource
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

# ... other relevant outputs

