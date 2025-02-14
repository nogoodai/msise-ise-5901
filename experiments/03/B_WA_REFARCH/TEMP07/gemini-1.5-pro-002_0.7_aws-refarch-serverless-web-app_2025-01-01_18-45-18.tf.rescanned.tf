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
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources in."
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack."
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application."

}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  default     = "master"
  description = "The branch of the GitHub repository."
}

variable "github_access_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token with appropriate permissions for Amplify."
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name                     = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length     = 12
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "OFF" # Consider enabling MFA for production

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code"]
  allowed_oauth_scopes                = ["email", "openid"]

  generate_secret = false
  callback_urls = ["http://localhost:3000/"] # Placeholder, replace with your frontend URL
  logout_urls    = ["http://localhost:3000/"] # Placeholder, replace with your frontend URL

    tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain      = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name             = "todo-table-${var.stack_name}"
  billing_mode      = "PAY_PER_REQUEST" # Use on-demand billing for cost optimization
  hash_key          = "cognito-username"
  range_key         = "id"


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

 point_in_time_recovery {
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
  name = "lambda_role_${var.stack_name}"

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
      }]
  })

  tags = {
    Name        = "lambda_role_${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# IAM Policy for Lambda to access DynamoDB and CloudWatch
resource "aws_iam_policy" "lambda_policy" {
 name = "lambda_policy_${var.stack_name}"
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
 "dynamodb:Query"

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

    tags = {
    Name        = "lambda_policy_${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# Placeholder for Lambda functions - replace with actual function code
resource "aws_lambda_function" "example_lambda" {
  filename         = "lambda_function.zip" # Replace with your function code
  function_name = "example_lambda_${var.stack_name}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler" # Replace with your handler
  runtime         = "nodejs16.x" # Replace with your runtime
  memory_size     = 1024
  timeout          = 60


  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "example_lambda_${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# API Gateway - Placeholder, needs to be expanded with actual API definitions
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
 minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Amplify App - Placeholder, requires GitHub repository URL
resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-amplify-${var.stack_name}"
  repository  = var.github_repo_url
 access_token = var.github_access_token
  build_spec = <<-EOT
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /dist # Replace with your build directory
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*

EOT

  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}




# Amplify Branch - Placeholder, adjust branch name if needed
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true


  tags = {
    Name        = "${var.application_name}-amplify-branch-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "dynamodb_table_name" {
 value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "amplify_app_id" {
 value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.main.id
  description = "The ID of the API Gateway."
}

output "lambda_function_arn" {
 value       = aws_lambda_function.example_lambda.arn
  description = "The ARN of the example Lambda function."
}
