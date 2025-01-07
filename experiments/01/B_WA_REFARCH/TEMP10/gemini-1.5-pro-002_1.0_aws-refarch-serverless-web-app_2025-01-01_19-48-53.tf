terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project" {
  type    = string
  default = "todo-app"
}

variable "stack_name" {
  type    = string
  default = "todo-app-stack"
}

variable "github_repo_url" {
  type    = string
  default = "https://github.com/your-username/your-repo.git"
}

variable "github_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project}-user-pool-${var.environment}"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.project}-user-pool-client-${var.environment}"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000"] # Placeholder - replace with actual callback URLs
  logout_urls                          = ["http://localhost:3000"] # Placeholder - replace with actual logout URLs
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project}-${var.stack_name}"
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


}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project}-api-${var.environment}"
  description = "API Gateway for ${var.project}"
}




resource "aws_amplify_app" "main" {
  name       = "${var.project}-amplify-app-${var.environment}"
  repository = var.github_repo_url
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
   baseDirectory: /
   files:
     - '**/*'
EOF

}

resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true
}

# IAM Roles and Policies

resource "aws_iam_role" "api_gateway_cw_log_role" {
  name = "${var.project}-api-gateway-cw-log-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
 Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
 Principal = {
          Service = "apigateway.amazonaws.com"
 }
      },
 ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cw_log_policy" {
  role       = aws_iam_role.api_gateway_cw_log_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}




# Outputs


output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}



output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}

