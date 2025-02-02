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

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}



# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  tags = {
    Name = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = var.stack_name
    Project = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  tags = {
    Name = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = var.stack_name
    Project = var.application_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = var.stack_name
    Project = var.application_name
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
 name = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
 read_capacity = 5
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

 server_side_encryption {
   enabled = true
 }

 tags = {
   Name = "todo-table-${var.stack_name}"
   Environment = var.stack_name
   Project = var.application_name
 }
}

# IAM Role for API Gateway Logging
resource "aws_iam_role" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

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

  tags = {
    Name = "api-gateway-cloudwatch-logs-${var.stack_name}"
    Environment = var.stack_name
    Project = var.application_name
  }
}


# IAM Policy for API Gateway Logging
resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}


# IAM Role for Lambda
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

 tags = {
   Name = "lambda-exec-role-${var.stack_name}"
   Environment = var.stack_name
   Project = var.application_name
 }
}

# IAM Policy for Lambda (DynamoDB and CloudWatch)
resource "aws_iam_policy" "lambda_policy" {
 name = "lambda-policy-${var.stack_name}"


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
   "dynamodb:Scan",
   "dynamodb:Query",
   "dynamodb:BatchWriteItem"
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
 Resource = "*"
 }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_attach_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}



# Placeholder for Lambda functions - replace with actual function code and deployments
# Example for "Add Item" function
resource "aws_lambda_function" "add_item_lambda" {
  function_name = "add-item-lambda-${var.stack_name}"
  handler = "index.handler" # Replace with your handler
  runtime = "nodejs16.x" # Or your preferred runtime
  memory_size = 1024
  timeout = 60
  role = aws_iam_role.lambda_exec_role.arn
 #  filename      = "path/to/your/lambda/code.zip" # Replace with your code
  source_code_hash = filebase64sha256("path/to/your/lambda/code.zip") # Replace with your code's hash

  tracing_config {
 mode = "Active"
  }

 tags = {
   Name = "add-item-lambda-${var.stack_name}"
   Environment = var.stack_name
   Project = var.application_name
 }
}



# Amplify App
resource "aws_amplify_app" "main" {
 name = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with a secure way to manage access tokens
 build_spec = <<-EOT
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
     baseDirectory: /dist
     files:
       - '**/*'
   cache:
     paths:
       - node_modules/**/*
 EOT


  tags = {
    Name = "${var.application_name}-amplify-${var.stack_name}"
    Environment = var.stack_name
    Project = var.application_name
  }
}



# Amplify Branch (auto-build enabled)
resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

  tags = {
    Name = "${var.application_name}-amplify-branch-${var.stack_name}"
    Environment = var.stack_name
    Project = var.application_name
  }
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

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}


