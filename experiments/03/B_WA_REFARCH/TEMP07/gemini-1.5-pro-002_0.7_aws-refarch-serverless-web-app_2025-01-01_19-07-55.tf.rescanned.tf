terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a more flexible version constraint
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "The AWS region to deploy the resources to."
  default     = "us-east-1"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack. Used as a prefix for resource names."
  default     = "serverless-todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}

variable "github_access_token" {
 type = string
 description = "GitHub personal access token with appropriate permissions for Amplify."
 sensitive = true
}

variable "tags" {
  type        = map(string)
 description = "A map of tags to apply to all resources."
 default = {
    Environment = "dev",
    Project     = "todo-app"
 }
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 12 # Increased minimum length for better security
    require_lowercase = true
    require_uppercase = true
    require_numbers = true # Require numbers in passwords
 require_symbols = true # Require symbols in passwords
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  mfa_configuration = "OPTIONAL" # Enable MFA

  tags = var.tags
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = var.tags
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
 allowed_oauth_flows = ["authorization_code"] # Removed implicit flow for enhanced security
 allowed_oauth_scopes = ["email", "openid"] # Removed phone scope

  generate_secret = false
  prevent_user_existence_errors = "ENABLED"
 refresh_token_validity = 30 # Reduced refresh token validity

  tags = var.tags
}


resource "aws_dynamodb_table" "main" {
 name         = "todo-table-${var.stack_name}"
 billing_mode = "PAY_PER_REQUEST" # Use on-demand billing
 hash_key = "cognito-username"
 range_key = "id"

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

 tags = var.tags

}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Action": "sts:AssumeRole",
   "Principal": {
    "Service": "apigateway.amazonaws.com"
   },
   "Effect": "Allow",
   "Sid": ""
  }
 ]
}
EOF

 tags = var.tags
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
 role = aws_iam_role.api_gateway_cloudwatch_role.id

 policy = jsonencode({
   "Version" : "2012-10-17",
   "Statement" : [
    {
     "Effect" : "Allow",
     "Action" : [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
     ],
      "Resource" : [ # Restrict resource access
       "arn:aws:logs:*:*:log-group:/aws/apigateway/*"
      ]
    }
   ]
 })


 tags = var.tags
}


resource "aws_accessanalyzer_analyzer" "analyzer" {
 analyzer_name = "${var.stack_name}-access-analyzer"
 type          = "ACCOUNT"

 tags = var.tags
}

# Placeholder for Lambda and API Gateway resources


resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo
 access_token = var.github_access_token

 build_spec = <<YAML
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
   baseDirectory: /
   files:
     - '**/*'
YAML
 oauth_token = var.github_access_token # Use a dedicated OAuth token for Amplify if available
 tags = var.tags
}

resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true

 tags = var.tags
}


output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
 description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
 description = "The ID of the Cognito User Pool Client."
}

output "cognito_user_pool_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
 description = "The domain of the Cognito User Pool."
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
 description = "The name of the DynamoDB table."
}


output "access_analyzer_arn" {
 value = aws_accessanalyzer_analyzer.analyzer.arn
 description = "The ARN of the IAM Access Analyzer."
}


