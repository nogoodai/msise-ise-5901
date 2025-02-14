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
  type        = string
  description = "The AWS region to deploy into."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "The name of the project."
}

variable "environment" {
  type        = string
  description = "The environment (e.g., dev, prod)."
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token with appropriate permissions."
  sensitive   = true
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length     = 12
    require_uppercase = true
    require_lowercase = true
    require_symbols   = true
    require_numbers   = true
  }

 mfa_configuration = "OFF" # Consider enabling MFA for enhanced security

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.main.id
  generate_secret = false

 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = ["authorization_code"]
  allowed_scopes        = ["email", "phone", "openid"]

  # Update callback and logout URLs with actual values
  callback_urls = ["https://example.com/callback"]
  logout_urls    = ["https://example.com/logout"]


  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-domain"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Use PAY_PER_REQUEST to avoid capacity planning issues.
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
 point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-${var.environment}-${var.stack_name}-api"
  description = "API Gateway for ${var.project_name}"
 minimum_compression_size = 0

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}



# Simplified Lambda function definition (replace with actual function code)

resource "aws_lambda_function" "example" {
  function_name = "my_function"
  handler       = "index.handler"
  runtime       = "nodejs16.x" # Updated runtime for latest Node.js
  role          = aws_iam_role.lambda_exec_role.arn

  # Replace with your actual function code or S3 bucket reference
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
  memory_size      = 1024
 timeout          = 300
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "my_function"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"
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
    Name        = "lambda_exec_role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
 policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api_gateway_cloudwatch_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
 Service = "apigateway.amazonaws.com"
 }
      }
    ]
  })
 tags = {
    Name        = "api-gateway-cloudwatch-role"
    Environment = var.environment
    Project     = var.project_name
 }
}


resource "aws_amplify_app" "main" {
  name       = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url
  access_token = var.github_access_token
  build_spec = jsonencode({
    version = 0.1,
    frontend = {
      phases = {
        preBuild  = "npm install",
        build     = "npm run build",
        postBuild = "npm run deploy"
      },
      artifacts = {
        baseDirectory = "/public",
        files        = ["**/*"]
      },
      cache = {
        paths = ["node_modules/**/*"]
      }
    }
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-app"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "main" {
  app_id          = aws_amplify_app.main.id
 branch_name      = var.github_repo_branch
 enable_auto_build = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-branch"
    Environment = var.environment
    Project     = var.project_name
  }
}


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

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.main.id
  description = "The ID of the API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
 description = "The ID of the Amplify app."
}

