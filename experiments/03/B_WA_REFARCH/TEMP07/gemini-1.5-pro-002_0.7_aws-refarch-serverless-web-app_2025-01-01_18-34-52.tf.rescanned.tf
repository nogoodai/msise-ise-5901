terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a version constraint
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The application name."

  default = "todo-app"
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "main" # Best practice: use main instead of master.
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
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length    = 12 # Increased minimum length
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true # Require numbers
    require_symbols   = true # Require symbols
  }

  mfa_configuration = "OPTIONAL" # Enable MFA
 auto_verified_attributes = ["email"]
  tags = var.tags
}


resource "aws_cognito_user_pool_client" "main" {
  name             = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id     = aws_cognito_user_pool.main.id
  generate_secret   = false
 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code"] # Removed implicit flow
  allowed_oauth_scopes                = ["email", "openid"] # Removed phone scope
  callback_urls = var.callback_urls
  logout_urls = var.logout_urls

}

variable "callback_urls" {
  type = list(string)
  description = "A list of callback URLs."
}
variable "logout_urls" {
  type = list(string)
  description = "A list of logout URLs."
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Use on-demand billing
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
  tags = var.tags


}




resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

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


resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"
  role = aws_iam_role.api_gateway_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}


resource "aws_apigateway_rest_api" "main" {
 name        = "todo-api-${var.stack_name}"
 tags = var.tags
}


resource "aws_apigateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
  rest_api_id   = aws_apigateway_rest_api.main.id
  type           = "COGNITO_USER_POOLS"
  provider_arns  = [aws_cognito_user_pool.main.arn]
}



# Placeholder for Lambda functions and API Gateway integrations.
# These would typically be defined using resources like aws_lambda_function,
# aws_apigateway_integration, aws_apigateway_method, and aws_apigateway_resource.


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url

  build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci # Use npm ci for deterministic builds
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
  tags = var.tags

}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}


resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "amplify.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
 tags = var.tags
}


# Replace AdministratorAccess with least privilege policy
resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
 policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess" # Replace with more restrictive policy
}

resource "aws_accessanalyzer_analyzer" "analyzer" {
  analyzer_name = "todo-app-analyzer"
  type          = "ACCOUNT"
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

output "dynamodb_table_name" {
 value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_id" {
  value       = aws_apigateway_rest_api.main.id
  description = "The ID of the API Gateway."
}

output "amplify_app_id" {
 value       = aws_amplify_app.main.id
  description = "The ID of the Amplify App."
}


