terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
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


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}


resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/"] # Placeholder, update with your actual callback URL
  logout_urls                          = ["http://localhost:3000/"] # Placeholder, update with your actual logout URL
  prevent_user_existence_errors       = "ENABLED"

}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}



resource "aws_dynamodb_table" "main" {
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

}

# API Gateway, Lambda, and Amplify resources are complex and require further refinement based on user feedback.
# Placeholder resources are provided to adhere to the 'single file' requirement.


# Placeholder for API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"

}


# Placeholder Lambda Function
resource "aws_lambda_function" "example" {
  function_name = "example-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs16.x"
 memory_size = 128
 timeout        = 30

  # Replace with your actual code and S3 bucket
 filename      = "lambda_function.zip"
 source_code_hash = filebase64sha256("lambda_function.zip")

 role          = aws_iam_role.lambda_exec_role.arn

}


# Placeholder IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role_${var.stack_name}"

 assume_role_policy = jsonencode({
   Version = "2012-10-17"
   Statement = [
     {
       Action = "sts:AssumeRole"
       Effect = "Allow"
       Principal = {
         Service = "lambda.amazonaws.com"
       }
     },
   ]
 })

}

# Placeholder IAM Policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
 name        = "lambda_policy_${var.stack_name}"
 path        = "/"
 description = "IAM policy for Lambda function"
 policy = jsonencode({
   Version = "2012-10-17"
   Statement = [
     {
       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents",
       ]
       Effect   = "Allow"
       Resource = "*"
     },
   ]
 })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
 role       = aws_iam_role.lambda_exec_role.name
 policy_arn = aws_iam_policy.lambda_policy.arn
}




# Placeholder for Amplify App
resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = "https://github.com/example/repo" # Replace with your actual repository URL
}



