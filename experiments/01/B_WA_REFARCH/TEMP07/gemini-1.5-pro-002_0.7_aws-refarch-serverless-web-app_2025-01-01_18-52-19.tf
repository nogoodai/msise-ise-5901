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
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
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

}



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
}


resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito-authorizer"
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
  rest_api_id    = aws_api_gateway_rest_api.main.id
  identity_source = "method.request.header.Authorization"
}



resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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
          "logs:PutLogEvents",
        ],
        Resource = "*"
      },
    ]
  })
}



resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
}



resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler" # Replace with your actual handler
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
 # replace with your code
  filename      = "dummy_lambda.zip"
 source_code_hash = filebase64sha256("dummy_lambda.zip")

  role = aws_iam_role.lambda_exec_role.arn


}

# Dummy zip file for lambda - replace with actual code
resource "null_resource" "lambda_zip" {
  provisioner "local-exec" {
    command = "zip dummy_lambda.zip dummy_lambda_code.js"
  }
}

resource "local_file" "lambda_code" {
 content = <<EOF
exports.handler = async (event) => {
  const response = {
    statusCode: 200,
    body: JSON.stringify('Hello from Lambda!'),
  };
  return response;
};
EOF
 filename = "dummy_lambda_code.js"
}




resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"


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
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
        ],
 Resource = aws_dynamodb_table.main.arn

      },
      {
 Effect = "Allow",
 Action = [
          "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
 ],
 Resource = "arn:aws:logs:*:*:*"
 }
    ]
  })
}



resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
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
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
}

resource "aws_amplify_branch" "master" {
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

