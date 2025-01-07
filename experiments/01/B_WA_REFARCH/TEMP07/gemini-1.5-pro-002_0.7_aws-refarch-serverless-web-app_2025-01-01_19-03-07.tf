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
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}

variable "domain_prefix" {
  type = string
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  email_verification_message = "Your verification code is: {####}"
  email_verification_subject = "Verify your email"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name      = "${var.stack_name}-cognito-user-pool"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls = ["http://localhost:3000/"] # Placeholder, update with actual callback URLs

  tags = {
    Name      = "${var.stack_name}-cognito-user-pool-client"
    Environment = "production"
    Project     = var.stack_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.domain_prefix}-${var.stack_name}"
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

  tags = {
    Name      = "${var.stack_name}-dynamodb-table"
    Environment = "production"
    Project     = var.stack_name
  }
}



# API Gateway, Lambda, Amplify, IAM Roles and Policies are complex and require more detailed information about lambda function code, build process etc. to generate accurate and complete Terraform code.  The following are placeholders that would need to be expanded.


resource "aws_api_gateway_rest_api" "main" {
  name = "${var.stack_name}-api"

  tags = {
    Name = "${var.stack_name}-api-gateway"
 Environment = "production"
 Project = var.stack_name
  }
}

# Placeholder for Lambda functions - needs detailed implementation
# resource "aws_lambda_function" "example" {
#   # ...
# }

# Placeholder for Amplify app - needs detailed implementation, including build settings
# resource "aws_amplify_app" "main" {
#   # ...
# }

# Placeholder for IAM roles and policies - needs fine-grained permissions based on actual resource usage
# resource "aws_iam_role" "api_gateway_role" {
#   # ...
# }


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}


