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

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "stack_name" {
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
  name                 = "${var.project_name}-${var.stack_name}-user-pool"
  username_attributes = ["email"]
  email_verification_message = "Your verification code is {####}"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                                = "${var.project_name}-${var.stack_name}-user-pool-client"
  user_pool_id                       = aws_cognito_user_pool.main.id
  generate_secret                    = false
  explicit_auth_flows                = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  callback_urls                      = ["https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/oauth2/idpResponse"]
  logout_urls                        = ["https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/logout"]
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes               = ["email", "phone", "openid"]

  depends_on = [aws_cognito_user_pool_domain.main]

}



resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo_table" {
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
   Name        = "todo-table"
   Environment = var.environment
   Project     = var.project_name
 }
}


resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"

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


resource "aws_iam_role_policy" "api_gateway_cw_policy" {
 name = "api-gateway-cw-policy-${var.stack_name}"
 role = aws_iam_role.api_gateway_cw_role.id

 policy = jsonencode({
 Version = "2012-10-17"
 Statement = [
  {
   Action = [
    "logs:CreateLogGroup",
    "logs:CreateLogStream",
    "logs:PutLogEvents"
   ]
   Resource = "*"
   Effect   = "Allow"
  }
 ]
 })
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}




resource "aws_iam_role" "lambda_role" {
 name = "lambda-role-${var.stack_name}"
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


 policy = jsonencode({
   Version = "2012-10-17"
   Statement = [
     {
       Action = [
         "dynamodb:GetItem",
         "dynamodb:PutItem",
         "dynamodb:UpdateItem",
         "dynamodb:DeleteItem",
         "dynamodb:Scan",
         "dynamodb:Query",
         "dynamodb:BatchGetItem",
         "dynamodb:BatchWriteItem",
         "dynamodb:DescribeTable"
       ]
       Resource = aws_dynamodb_table.todo_table.arn
       Effect   = "Allow"
     },
     {
       Action = [
         "cloudwatch:PutMetricData"
       ],
       Resource = "*",
       Effect = "Allow"
     },
     {
       Action = [
         "xray:PutTraceSegments",
         "xray:PutTelemetryRecords"
       ],
       Resource = "*",
       Effect = "Allow"
     }
   ]
 })

}



resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



data "archive_file" "lambda_zip" {
 type        = "zip"
 source_dir  = "../lambda-functions" # Replace with the actual path of the folder where lambda functions are defined
 output_path = "lambda.zip"
}


resource "aws_lambda_function" "add_item_lambda" {
 function_name = "addItem-${var.stack_name}"
 handler       = "index.handler"
 runtime       = "nodejs12.x"
 memory_size   = 1024
 timeout       = 60
 role          = aws_iam_role.lambda_role.arn

 filename         = data.archive_file.lambda_zip.output_path
 source_code_hash = data.archive_file.lambda_zip.output_base64sha256

 tracing_config {
   mode = "Active"
 }


 environment {
   variables = {
     TABLE_NAME = aws_dynamodb_table.todo_table.name
   }
 }

 tags = {
   Name        = "addItem-lambda"
   Environment = var.environment
   Project     = var.project_name
 }
}



resource "aws_amplify_app" "main" {
 name       = "${var.project_name}-app-${var.stack_name}"
 repository = var.github_repo_url
}


resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true

 build_spec = <<YAML
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
  baseDirectory: /build
  files:
    - '**/*'
YAML
}



output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.client.id
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



