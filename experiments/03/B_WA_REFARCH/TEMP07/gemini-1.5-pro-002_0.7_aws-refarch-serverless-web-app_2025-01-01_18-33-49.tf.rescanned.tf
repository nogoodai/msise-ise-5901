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
  description = "The AWS region to deploy the resources to."
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack. Used for naming resources."
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository to use."
  default     = "master"
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
    minimum_length = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
 require_symbols = true
  }

  mfa_configuration = "OFF" # Consider using "ON" or "OPTIONAL" for production



  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = var.tags

}

resource "aws_cognito_user_pool_client" "client" {
  name                                 = "${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code"]
  allowed_oauth_scopes                 = ["email", "openid"]
  callback_urls                        = var.callback_urls # Replace with your actual callback URLs
  logout_urls                          = var.logout_urls # Replace with your actual logout URLs
  prevent_user_existence_errors       = "ENABLED"

  tags = var.tags
}

variable "callback_urls" {
 type = list(string)
 description = "A list of callback URLs for the Cognito User Pool Client."
}

variable "logout_urls" {
  type        = list(string)
  description = "A list of logout URLs for the Cognito User Pool Client."
}



resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${var.region}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = var.tags
}


resource "aws_dynamodb_table" "todo_table" {
 name           = "todo-table-${var.stack_name}"
 billing_mode   = "PAY_PER_REQUEST"

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




resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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

  tags = var.tags
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
 Resource = ["arn:aws:logs:*:*:log-group:/aws/apigateway/*"] # Restrict resource to only apigateway logs
      },
    ]
  })


  tags = var.tags
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
 minimum_compression_size = 0

 tags = var.tags
}



resource "aws_amplify_app" "main" {
  name       = "${var.stack_name}-amplify-app"
  repository = var.github_repo
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
   baseDirectory: /build
   files:
     - '**/*'
EOF
  tags = var.tags

}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
 enable_auto_build = true

  tags = var.tags
}

resource "aws_accessanalyzer_analyzer" "analyzer" {
 analyzer_name = "${var.stack_name}-analyzer"
  type = "ACCOUNT"
 tags = var.tags
}




# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.client.id
  description = "The ID of the Cognito User Pool Client."
}

output "cognito_user_pool_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "The domain of the Cognito User Pool."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
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

output "accessanalyzer_arn" {
 value = aws_accessanalyzer_analyzer.analyzer.arn
 description = "The ARN of the Access Analyzer."
}

