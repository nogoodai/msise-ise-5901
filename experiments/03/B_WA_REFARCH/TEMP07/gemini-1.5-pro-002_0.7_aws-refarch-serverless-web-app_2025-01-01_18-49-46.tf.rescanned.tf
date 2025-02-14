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

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
  sensitive   = true
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token."
  sensitive   = true
}

# Cognito
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
  mfa_configuration = "OFF" # Consider enforcing MFA for better security
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev"
    Project     = var.application_name
  }

}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                      = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls                       = ["http://localhost:3000/"] # Replace with your logout URLs
  supported_identity_types          = ["COGNITO"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-domain"
    Environment = "dev"
    Project     = var.application_name
  }
}

# DynamoDB
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

 point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}


# IAM Roles
resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

  assume_policy = jsonencode({
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
    tags = {
    Name        = "api-gateway-cloudwatch-logs-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
  name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs_role.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
        Resource = "*",
 Effect = "Allow"
      }
    ]
  })
}


# Lambda (Placeholder - needs actual Lambda code deployment)
#  You'll need to replace the filename with your actual Lambda zip file.
resource "aws_lambda_function" "add_item" {
 filename      = "lambda_function.zip" # Replace with your Lambda zip file
 function_name = "add-item-${var.stack_name}"
 handler       = "index.handler" # Replace with your handler
 runtime       = "nodejs12.x"
  memory_size = 1024
 timeout       = 60

 role          = aws_iam_role.lambda_exec_role.arn # Create this role
  tracing_config {
    mode = "Active"
  }
 tags = {
    Name        = "add-item-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }

 # Add appropriate environment variables, VPC config, etc. as needed
}
# Create similar resources for other Lambda functions

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"
 assume_policy = jsonencode({
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
  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy-${var.stack_name}"
  role = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
 Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
 "dynamodb:Scan" # Consider replacing with Query for better performance
 ],
 Resource = aws_dynamodb_table.main.arn,
        Effect = "Allow"
      }
    ]
  })
}

# Amplify (Example - needs adjustments for GitHub integration)
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
 repository = var.github_repo
  access_token = var.github_access_token


  build_spec = <<EOF
version: 0.1
phases:
 install:
    commands:
      - npm install
 build:
 commands:
 - npm run build
 artifacts:
    base_directory: build
    files:
 - '**/*'
EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-branch"
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

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

