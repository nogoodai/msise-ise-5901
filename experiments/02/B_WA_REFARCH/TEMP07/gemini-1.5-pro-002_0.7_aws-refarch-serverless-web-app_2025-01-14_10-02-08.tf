terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type = string
}

variable "application_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name            = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id  = aws_cognito_user_pool.main.id
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls = ["http://localhost:3000/"] # Placeholder, update as needed

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
}

resource "aws_iam_role" "api_gateway_cw_logs_role" {
  name = "api-gateway-cw-logs-role-${var.stack_name}"

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

resource "aws_iam_role_policy" "api_gateway_cw_logs_policy" {
  name = "api-gateway-cw-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_logs_role.id

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
        Resource = "*"
      },
    ]
  })
}


resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}"
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with a secure method for handling secrets

 build_spec = jsonencode({
    version = 0.1,
    frontend = {
 phases = {
        preBuild  = "npm install",
        build     = "npm run build",
 deploy = "echo 'Deploying...'"
      },
 artifacts = {
 baseDirectory = "build",
        files = ["**/*"]
      },
      cache = {
 paths = ["node_modules/**/*"]
      }
    }
  })

}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}


# Placeholder for Lambda and API Gateway resources.  These require significantly more detail
# regarding the API implementation to create secure and effective Terraform.  Provide
# more details about the Lambda function code and API Gateway endpoints for a complete
# and secure solution.



