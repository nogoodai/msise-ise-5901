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
  description = "The AWS region to deploy the resources in."
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}


variable "github_access_token" {
  type        = string
  description = "GitHub Personal Access Token"
  sensitive   = true

}


variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}

variable "callback_urls" {
  type        = list(string)
  description = "List of callback URLs."
  default = ["http://localhost:3000/"]
}

variable "logout_urls" {
  type        = list(string)
  description = "List of logout URLs."
  default = ["http://localhost:3000/"]
}

resource "random_id" "main" {
  byte_length = 8
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration = "OFF" # Explicitly set MFA to OFF
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "dev" # Example environment tag, replace as needed
    Project     = "todo-app" # Example project tag, replace as needed
  }

}

resource "aws_cognito_user_pool_client" "main" {
  name                        = "${var.stack_name}-user-pool-client"
  user_pool_id               = aws_cognito_user_pool.main.id
  generate_secret             = false
  allowed_oauth_flows        = ["authorization_code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls               = var.callback_urls
  logout_urls                 = var.logout_urls
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_id.main.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}



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
    Environment = "dev" # Example environment tag, replace as needed
    Project     = "todo-app" # Example project tag, replace as needed
  }
}


resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"

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
  tags = {
    Name        = "api-gateway-cw-role-${var.stack_name}"
    Environment = "dev" # Example environment tag, replace as needed
    Project     = "todo-app" # Example project tag, replace as needed
 }
}


resource "aws_iam_role_policy" "api_gateway_cw_policy" {
  name = "api-gateway-cw-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_role.id

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



resource "aws_api_gateway_rest_api" "main" {
 name        = "todo-api-${var.stack_name}"
 description = "API Gateway for Todo App"

 minimum_compression_size = 0

 tags = {
    Name        = "todo-api-${var.stack_name}"
    Environment = "dev" # Example environment tag, replace as needed
    Project     = "todo-app" # Example project tag, replace as needed
  }

}



resource "aws_amplify_app" "main" {
  name       = "${var.stack_name}-amplify-app"
  repository = var.github_repo
  access_token = var.github_access_token

}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  stage = "PRODUCTION"

  enable_auto_build = true

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
  baseDirectory: build
  files:
   - '**/*'
YAML
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

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
 description = "The ID of the API Gateway."
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
 description = "The ID of the Amplify App."
}
