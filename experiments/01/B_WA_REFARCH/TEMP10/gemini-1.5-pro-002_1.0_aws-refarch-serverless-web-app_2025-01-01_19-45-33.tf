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


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

 email_verification_message = "Your verification code is {####}"
 email_verification_subject = "Verify your email"
 mfa_configuration = "OFF"
 sms_authentication_message = "Your verification code is {####}"
 sms_verification_message = "Your verification code is {####}"
 username_attributes = ["email"]
 verification_message_template {
    default_email_options {
      sms_message = "Your verification code is {####}"
    }
  }

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }
}


resource "aws_cognito_user_pool_client" "client" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

 allowed_oauth_flows_user_pool_client = true
 allowed_oauth_flows = ["code", "implicit"]
 allowed_oauth_scopes = ["phone", "email", "openid", "profile"]
 callback_urls = ["http://localhost:3000/"] # Placeholder - update with actual frontend URL
 generate_secret = false
  refresh_token_validity = 30
  supported_identity_providers = ["COGNITO"]


}

resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}




resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 point_in_time_recovery {
    enabled = false
  }
 read_capacity = 5
  server_side_encryption {
 enabled = true
  }
 write_capacity = 5
 attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
 type = "S"
  }
 hash_key = "cognito-username"
  range_key = "id"

 tags = {
    Name        = "todo-table-${var.stack_name}"
 Environment = "prod"
    Project     = var.application_name
  }
}


# Placeholder resources - Replace with actual Lambda function code and deployment
resource "aws_lambda_function" "example" {
  # ... (Lambda function configuration)
  filename      = "lambda_function.zip"
  function_name = "example-${var.stack_name}"
  handler       = "index.handler"
 role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs12.x"


  tags = {
    Name        = "example-${var.stack_name}"
 Environment = "prod"
    Project     = var.application_name
  }
}




resource "aws_iam_role" "lambda_role" {
  name = "lambda_role-${var.stack_name}"

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

 tags = {
    Name        = "lambda_role-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
 }
}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
 policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" # Replace with more restrictive policy in production
  role       = aws_iam_role.lambda_role.name
}



# Placeholder for API Gateway configuration - Need actual API definition
resource "aws_api_gateway_rest_api" "main" {
  name        = "api-${var.stack_name}"


  tags = {
    Name        = "api-${var.stack_name}"
    Environment = "prod"
 Project     = var.application_name
  }
}


# ... (Rest of the API Gateway, Amplify, and IAM resources)


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.client.id
}


output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}



