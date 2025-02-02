terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}



# Cognito User Pool
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


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  explicit_auth_flows               = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes              = ["email", "phone", "openid"]
  generate_secret                   = false
  prevent_user_existence_errors = "ENABLED"
  supported_identity_providers = ["COGNITO"]


  callback_urls        = ["http://localhost:3000/"] # Placeholder, replace with actual callback URL
  logout_urls          = ["http://localhost:3000/"] # Placeholder, replace with actual logout URL
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_id.domain_suffix.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_id" "domain_suffix" {
  byte_length = 4
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

}


# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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

# IAM Policy for Lambda (DynamoDB and CloudWatch)

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.stack_name}-lambda-dynamodb-policy"
  description = "Policy for Lambda functions to access DynamoDB and CloudWatch"

 policy = jsonencode({
   Version = "2012-10-17",
   Statement = [
     {
       Action = [
         "dynamodb:BatchGetItem",
         "dynamodb:GetItem",
         "dynamodb:Query",
         "dynamodb:Scan",
         "dynamodb:BatchWriteItem",
         "dynamodb:PutItem",
         "dynamodb:UpdateItem",
         "dynamodb:DeleteItem",
       ],
       Effect   = "Allow",
       Resource = aws_dynamodb_table.main.arn
     },
     {
       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents",
         "cloudwatch:PutMetricData",
       ],
       Effect = "Allow",
       Resource = "*"
     },
   ]
 })
}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# Lambda functions (placeholders - replace with actual code)

resource "aws_lambda_function" "add_item" {
  filename      = "add_item.zip" # Placeholder, replace with actual filename
  function_name = "${var.stack_name}-add-item"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler" # Placeholder, replace with actual handler
  runtime       = "nodejs16.x"
  memory_size   = 1024
 timeout        = 60

  # ... other Lambda function configurations (environment variables, etc.)
}



# API Gateway (simplified example)
resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.stack_name}-api"
 description = "API Gateway for ${var.stack_name}"
}

# ... API Gateway resources, methods, integrations (connect to Lambda functions)

# Amplify App
resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with a secure way to manage access tokens

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
     postBuild:
       commands:
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
 EOF


}

resource "aws_s3_bucket" "main" { # Secure S3 bucket for Amplify artifacts
 bucket = "${var.stack_name}-amplify-artifacts"

 server_side_encryption_configuration {
   rule {
     apply_server_side_encryption_by_default {
       sse_algorithm = "AES256"
     }
   }
 }

 versioning {
   enabled = true
 }
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

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}



output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


