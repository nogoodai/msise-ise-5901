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

variable "github_repo_branch" {
  type    = string
  default = "master"
}



# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false

  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  callback_urls                        = ["http://localhost:3000/"] # Placeholder
  logout_urls                          = ["http://localhost:3000/"] # Placeholder
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]
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



# IAM Role for API Gateway Logging
resource "aws_iam_role" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

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

# IAM Policy for API Gateway Logging
resource "aws_iam_policy" "api_gateway_cloudwatch_logs" {

 name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"

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
      },
    ]
  })
}

# Attach IAM Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs" {
  role       = aws_iam_role.api_gateway_cloudwatch_logs.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_logs.arn
}



# IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {

  name = "lambda-exec-role-${var.stack_name}"


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
resource "aws_iam_policy" "lambda_dynamodb_cloudwatch" {
  name = "lambda-dynamodb-cloudwatch-policy-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = [
 "dynamodb:GetItem",
 "dynamodb:PutItem",
 "dynamodb:DeleteItem",
 "dynamodb:UpdateItem",
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
 Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
 "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })
}


# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_cloudwatch" {
 role       = aws_iam_role.lambda_exec.name
 policy_arn = aws_iam_policy.lambda_dynamodb_cloudwatch.arn
}


# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo_url
  access_token = var.github_personal_access_token # Sensitive variable

}




# IAM Role for Amplify
resource "aws_iam_role" "amplify" {
  name = "amplify-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
 Principal = {
          Service = "amplify.amazonaws.com"
 }
      },
    ]
 })
}



# Amplify Branch - Assuming a build settings from the Amplify console
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}


variable "github_personal_access_token" {
 type = string
 sensitive = true
 description = "Github Personal Access Token"
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


