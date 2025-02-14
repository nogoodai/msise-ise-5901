terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
  description = "The AWS region to deploy resources into."
}

variable "environment" {
  type    = string
  default = "dev"
  description = "The environment name (e.g., dev, staging, prod)."

}

variable "project" {
  type    = string
  default = "todo-app"
  description = "The project name."
}

variable "application_name" {
  type    = string
  default = "todo-app"
  description = "The application name."
}

variable "stack_name" {
  type    = string
  default = "todo-stack"
  description = "The stack name."
}

variable "github_repo_url" {
  type = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type    = string
  default = "main"
  description = "The branch of the GitHub repository."
}

variable "build_spec" {
  type = string
  description = "Amplify application build specification."
}

variable "github_access_token" {
  type = string
  description = "GitHub personal access token."
  sensitive = true
}

variable "allowed_callback_urls" {
  type    = list(string)
  default = ["http://localhost:3000/"]
  description = "Allowed callback URLs for the Cognito User Pool Client."
}

variable "dynamodb_pitr_enabled" {
  type    = bool
  default = true
  description = "Enable Point-in-time recovery for DynamoDB"
}



provider "aws" {
  region = var.region
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.environment}"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  username_attributes = ["email"]

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  auto_verified_attributes = ["email"]

 mfa_configuration = "OFF" # Consider setting to "ON" for production


  tags = {
    Name        = "${var.application_name}-cognito-user-pool"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name              = "${var.application_name}-app-client"
  user_pool_id      = aws_cognito_user_pool.main.id
  generate_secret   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["phone", "email", "openid"]
  callback_urls                       = var.allowed_callback_urls


  tags = {
    Name        = "${var.application_name}-cognito-user-pool-client"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_dynamodb_table" "todo_table" {
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

 point_in_time_recovery {
    enabled = var.dynamodb_pitr_enabled
 }
 server_side_encryption {
   enabled = true
 }

  tags = {
    Name        = "${var.application_name}-dynamodb-table"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      },
    ]
  })

  tags = {
    Name        = "${var.application_name}-api-gateway-cloudwatch-role"
    Environment = var.environment
    Project     = var.project
  }
}



resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"


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
        Resource = "*" # Limit resource access in production
      },
    ]
  })


  tags = {
    Name        = "${var.application_name}-api-gateway-cloudwatch-policy"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}




# Placeholder for Lambda functions and API Gateway - Requires more detailed API definition
# ...


resource "aws_amplify_app" "main" {
 name              = "${var.application_name}-amplify-app"
 repository        = var.github_repo_url
 access_token      = var.github_access_token
 build_spec = var.build_spec

  tags = {
    Name        = "${var.application_name}-amplify-app"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-amplify-branch"
    Environment = var.environment
    Project     = var.project
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
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table."
}




