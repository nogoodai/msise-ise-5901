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
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  generate_secret                    = false
  callback_urls                     = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls                        = ["http://localhost:3000/"] # Placeholder, update as needed

}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_id.main.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "random_id" "main" {
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


# IAM Role for API Gateway logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-api-gateway-cw-role"
 assume_role_policy = jsonencode({
   Version = "2012-10-17",
   Statement = [
     {
       Action = "sts:AssumeRole",
       Effect = "Allow",
       Principal = {
         Service = "apigateway.amazonaws.com"
       }
     },
   ]
 })
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "${var.stack_name}-api-gateway-cw-policy"
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
       Effect   = "Allow",
       Resource = "*"
     },
   ]
 })
}


# IAM Role for Lambda functions
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
      }
    ]
  })

}

# Policy for Lambda to access DynamoDB and CloudWatch
resource "aws_iam_policy" "lambda_dynamodb_cloudwatch_policy" {
 name = "${var.stack_name}-lambda-dynamodb-cw-policy"
 policy = jsonencode({
   Version = "2012-10-17",
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
       ],
       Effect   = "Allow",
       Resource = aws_dynamodb_table.main.arn
     },

     {
       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents",
         "cloudwatch:PutMetricData"
       ],
 Effect = "Allow",
 Resource = "*"
     }
   ]
 })
}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_cloudwatch_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_cloudwatch_policy.arn
}



# Placeholder for Lambda functions (replace with actual function code)
resource "aws_lambda_function" "example_lambda" {
 filename      = "lambda_function.zip" # Replace with your Lambda function code
 function_name = "${var.stack_name}-example-lambda"
 role          = aws_iam_role.lambda_role.arn
 handler       = "index.handler"
 runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60
 tracing_config {
   mode = "Active"
 }

 # Add environment variables, VPC configuration, and other settings as needed
}


# Amplify App
resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token
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


resource "aws_s3_bucket" "main" {
  bucket = "${var.stack_name}-bucket"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
      }
    }
  }

  versioning {
    enabled = true
  }
}


# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true

}


# API Gateway (Placeholder - Needs expansion based on the API definition)
# This requires more details on the API Gateway configuration
# including resources, methods, integration with Lambda functions, etc.




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

output "s3_bucket_name" {
  value = aws_s3_bucket.main.bucket
}
