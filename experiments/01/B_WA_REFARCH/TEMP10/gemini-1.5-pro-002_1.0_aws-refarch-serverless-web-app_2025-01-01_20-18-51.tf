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
  default = "todo-app"
}

variable "github_repo" {
  type    = string
  default = "your-github-repo" # Replace with your GitHub repository URL
}

variable "github_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
    temporary_password_validity_days = 7
  }

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                 = true
    name                    = "email"
    required                = true


  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls        = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls          = ["http://localhost:3000/"] # Replace with your logout URLs
  supported_identity_providers = ["COGNITO"]
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

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

}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  rest_api_id    = aws_api_gateway_rest_api.main.id
 provider_arns  = [aws_cognito_user_pool.main.arn]

}


# Example Lambda function (you'll need to create separate resources for each function)
resource "aws_lambda_function" "add_item" {
  # ... (Lambda function configuration) ...
}

# ... (Other Lambda functions: get_item, get_all_items, update_item, complete_item, delete_item) ...

# Example API Gateway integration (you'll need to create integrations for each Lambda function)
resource "aws_api_gateway_integration" "add_item" {
  # ... (API Gateway integration configuration) ...
}

# ... (Other API Gateway integrations) ...

resource "aws_amplify_app" "main" {
 name         = "${var.stack_name}-amplify-app"

 repository   = var.github_repo
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

  # ... (build settings) ...
}

# Example IAM role and policy for Lambda (you'll need to create separate roles/policies for other resources)
resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"
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
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  # ... (IAM policy for Lambda) ...
}

# Output important values
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

# ... (Other outputs) ...

