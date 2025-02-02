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
  default = "us-east-1"
}

variable "stack_name" {
  type = string
}

variable "application_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_branch_name" {
  type    = string
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.main.id
  generate_secret     = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls                          = ["http://localhost:3000/"] # Placeholder, update as needed

  supported_identity_providers = ["COGNITO"] # Important for security
}


# DynamoDB Table
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

 tags = {
   Name        = "todo-table-${var.stack_name}"
   Environment = var.stack_name
   Project     = var.application_name
 }
}

# IAM Role and Policy for Lambda
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
}


resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "${var.application_name}-${var.stack_name}-lambda-dynamodb-policy"
 policy = jsonencode({
 Version = "2012-10-17",
 Statement = [
 {
 Action = [
 "dynamodb:GetItem",
 "dynamodb:PutItem",
 "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
 "dynamodb:Scan", # Add Scan for Get All Items
 "dynamodb:Query",
 ],
 Effect = "Allow",
 Resource = aws_dynamodb_table.main.arn
 },
   {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/*"
      }
 ]
 })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


# Placeholder for Lambda functions - Replace with actual function code
resource "aws_lambda_function" "example_lambda" {
 filename     = "lambda_function.zip" # Replace with your zipped function code
 function_name = "${var.application_name}-${var.stack_name}-example-lambda"
 role          = aws_iam_role.lambda_role.arn
 handler       = "index.handler" # Replace with your handler
 runtime = "nodejs12.x" # Adjust as needed
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
   Name        = "${var.application_name}-${var.stack_name}-example-lambda"
   Environment = var.stack_name
   Project     = var.application_name
 }
}



# Amplify App
resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url
 access_token = "your_github_personal_access_token" # Replace with a secure solution
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
     postBuild:
       commands:
         - echo "PostBuild phase"
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF
 tags = {
   Name        = "${var.application_name}-${var.stack_name}-amplify-app"
   Environment = var.stack_name
   Project     = var.application_name
 }
}

# Amplify Branch
resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch_name
 enable_auto_build = true
}


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

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}


