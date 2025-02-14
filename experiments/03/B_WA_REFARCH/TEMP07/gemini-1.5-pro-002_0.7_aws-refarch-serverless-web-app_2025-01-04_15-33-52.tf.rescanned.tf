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
  default     = "us-east-1"
  description = "The AWS region to deploy the resources to."
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
  description = "GitHub personal access token with appropriate permissions."
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  username_attributes      = ["email"]
  mfa_configuration = "OFF" # Consider enabling MFA for production
  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }


  password_policy {
    minimum_length     = 12 # Increased minimum length
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true # Require numbers
    require_symbols   = true # Require symbols
  }

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "main" {
  name                         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                 = aws_cognito_user_pool.main.id
  generate_secret              = false
  allowed_oauth_flows          = ["authorization_code"] # Removed implicit flow for enhanced security
  allowed_oauth_scopes         = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls                = ["http://localhost:3000"] # Replace with your callback URLs
  logout_urls                 = ["http://localhost:3000"] # Replace with your logout URLs

  prevent_user_existence_errors = "ENABLED" # Prevent user enumeration

}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Use on-demand billing for cost optimization
  hash_key       = "cognito-username"
  range_key      = "id"
 tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "dev"
 Project     = var.application_name
  }


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
}



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
 minimum_compression_size = 0

  tags = {
 Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
 }

}


resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id  = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"
 tags = {
    Name        = "api-gateway-cloudwatch-role-${var.stack_name}"
 Environment = "dev"
    Project     = var.application_name
  }

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
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

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
        Resource = "*" # Replace with more specific resource in production
      },
    ]
  })
}


resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role-${var.stack_name}"
  tags = {
 Name        = "lambda-execution-role-${var.stack_name}"
    Environment = "dev"
 Project     = var.application_name
  }


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

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_execution_role.name
 policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" # Replace with more restrictive policy in production
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy" {
 role       = aws_iam_role.lambda_execution_role.name
 policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess" # Replace with more restrictive policy in production
}

# Placeholder for Lambda functions - replace with actual function code and configuration
# Example:
# resource "aws_lambda_function" "add_item" {
#   # ...
# }


resource "aws_amplify_app" "main" {
  name      = "${var.application_name}-amplify-${var.stack_name}"
  repository  = var.github_repo_url
  access_token = var.github_access_token
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
  artifacts:
 baseDirectory: build
    files:
      - '**/*'
cache:
  paths:
 - node_modules/**/*
EOF
}


resource "aws_amplify_branch" "master" {
  app_id           = aws_amplify_app.main.id
 branch_name      = var.github_repo_branch
  enable_auto_build = true

}

resource "aws_accessanalyzer_analyzer" "main" {
 analyzer_name = "${var.application_name}-analyzer"
  type          = "ACCOUNT"
 tags = {
    Name        = "${var.application_name}-analyzer"
    Environment = "dev"
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

output "api_gateway_id" {
 value       = aws_api_gateway_rest_api.main.id
  description = "The ID of the API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}
