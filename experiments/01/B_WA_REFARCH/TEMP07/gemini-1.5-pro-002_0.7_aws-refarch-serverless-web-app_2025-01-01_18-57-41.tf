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
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}


resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls = ["http://localhost:3000/"] # Replace with your actual callback URLs
  logout_urls   = ["http://localhost:3000/"] # Replace with your actual logout URLs

  # Prevent Terraform from constantly changing this resource
  prevent_destroy = false
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "main" {
 name         = "todo-table-${var.stack_name}"
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

 tags = {
   Name = "todo-table"
 }
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
       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents"
       ],
       Resource = "*",
       Effect   = "Allow"
     }
   ]
 })
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"
}


resource "aws_iam_role" "lambda_execution_role" {
 name = "lambda-execution-role-${var.stack_name}"
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
 Effect = "Allow",
 Action = [
 "dynamodb:GetItem",
 "dynamodb:PutItem",
 "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
 "dynamodb:BatchGetItem",
 "dynamodb:BatchWriteItem",
 "dynamodb:Query",
 "dynamodb:Scan"
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



resource "aws_iam_policy_attachment" "lambda_dynamodb_attachment" {
 name       = "lambda-dynamodb-attachment-${var.stack_name}"
 roles      = [aws_iam_role.lambda_execution_role.name]
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



resource "aws_lambda_function" "example" {
 # ... (Lambda function configurations for all CRUD operations)
 # Placeholder - Replace with actual Lambda function code and configurations
 filename      = "lambda_function.zip" # Replace with your Lambda function zip file
 function_name = "example-${var.stack_name}"
 role          = aws_iam_role.lambda_execution_role.arn
 handler       = "index.handler"  # Replace with your handler
 source_code_hash = filebase64sha256("lambda_function.zip")
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

 tags = {
   Name = "example-lambda"
 }
}





# (API Gateway resources, methods, integrations, authorizer, stage, usage plan)
# ... (Amplify app and branch resources)
# ... (IAM roles and policies for Amplify)




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
  value = aws_api_gateway_rest_api.main.id
}

