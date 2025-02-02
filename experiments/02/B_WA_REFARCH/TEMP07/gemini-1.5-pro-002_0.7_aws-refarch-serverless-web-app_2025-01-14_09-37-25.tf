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
  default = "todo-app-stack"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}



# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls                          = ["http://localhost:3000/"] # Placeholder, update as needed
  supported_identity_providers         = ["COGNITO"]
  prevent_user_existence_errors = "ENABLED"


}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode = "provisioned"
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
   Name        = "todo-table-${var.stack_name}"
   Environment = "prod"
   Project     = var.application_name
 }
}


# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-role"

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
    Name        = "${var.application_name}-${var.stack_name}-lambda-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

# IAM Policy for Lambda to access DynamoDB and CloudWatch
resource "aws_iam_policy" "lambda_policy" {

  name = "${var.application_name}-${var.stack_name}-lambda-policy"
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
          "dynamodb:Scan",
        ],
        Resource = aws_dynamodb_table.main.arn
      },
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
 ],
        Resource = "arn:aws:logs:*:*:*",
        Effect   = "Allow"
 }
    ]
  })
}




# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}



# Placeholder for Lambda functions - Replace with actual Lambda function code and configurations
resource "aws_lambda_function" "example_lambda" {
  # ... (Lambda function configuration) ...


  filename      = data.archive_file.lambda_zip.output_path
  function_name = "example-lambda-function"
  handler       = "index.handler" # Replace with your handler
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs12.x"
  # ... other Lambda configurations ...
}




# Placeholder for API Gateway - Replace with actual API Gateway configurations
resource "aws_api_gateway_rest_api" "example_api" {
  # ... (API Gateway configuration) ...
  name        = "${var.application_name}-${var.stack_name}-api"
}




# Placeholder for Amplify App - Replace with actual Amplify App configurations
resource "aws_amplify_app" "example_app" {
  # ... (Amplify App configuration) ...
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url

  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with a secure method to manage GitHub access tokens
}


output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}


