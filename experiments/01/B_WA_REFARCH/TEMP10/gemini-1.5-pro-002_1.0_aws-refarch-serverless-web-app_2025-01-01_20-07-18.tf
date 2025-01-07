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
  default = "serverless-todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type    = string
  default = "your-github-repo"
}

# Cognito Resources

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  username_attributes = ["email"]

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

  verification_message_template {
    default_email_options {
      sms_message = "Your verification code is {####}"
    }
  }

 schema {
    attribute_data_type      = "String"
    developer_only           = false
    mutable                  = true
    name                     = "email"
    number_attribute_constraints {
      max_value = "256"
      min_value = "0"
    }
    required                 = true
    string_attribute_constraints {
      max_length = "256"
      min_length = "0"
    }
  }

  password_policy {
 minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
 temporary_password_validity_days = 7
  }

  auto_verified_attributes = ["email"]
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
  allowed_oauth_scopes                = ["phone", "email", "openid"]

  generate_secret = false
}


# DynamoDB Table

resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
 read_capacity = 5
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

# IAM Roles and Policies

resource "aws_iam_role" "api_gateway_cloudwatch_logs" {
 name = "api-gateway-cloudwatch-logs-${var.stack_name}"

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


resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs" {
 name = "api-gateway-cloudwatch-logs-${var.stack_name}"
 role = aws_iam_role.api_gateway_cloudwatch_logs.id


 policy = jsonencode({
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
 })
}

resource "aws_iam_role" "lambda_execution_role" {
 name = "lambda-execution-role-${var.stack_name}"


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
 "Version": "2012-10-17",
 "Statement": [
  {
 "Effect": "Allow",
 "Action": [
 "dynamodb:GetItem",
  "dynamodb:PutItem",
 "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
 "dynamodb:Scan",
  "dynamodb:Query",
  "dynamodb:BatchGetItem",
  "dynamodb:BatchWriteItem",
  "dynamodb:ConditionCheckItem"
 ],
 "Resource": aws_dynamodb_table.main.arn
 },
 {
  "Effect": "Allow",
 "Action": "cloudwatch:PutMetricData",
 "Resource": "*"
 }
 ]
 })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



# API Gateway


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito_authorizer"
 provider_arns  = [aws_cognito_user_pool.main.arn]
  rest_api_id    = aws_api_gateway_rest_api.main.id
 type            = "COGNITO_USER_POOLS"

}



# Lambda Functions (Placeholder - Replace with actual Lambda function deployment)

# Amplify App

# Outputs

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}


