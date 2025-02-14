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
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources to."
}

variable "project_name" {
  type        = string
  description = "The name of the project."
}

variable "environment" {
  type        = string
  description = "The environment (e.g., dev, prod)."
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  default     = "master"
  description = "The branch of the GitHub repository."
}


variable "github_access_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token with appropriate permissions."
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }

  mfa_configuration = "OFF" # Consider changing to "ON" or "OPTIONAL" for production

 auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.project_name}-user-pool-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.project_name}-user-pool-client-${var.stack_name}"

  user_pool_id       = aws_cognito_user_pool.main.id
  generate_secret    = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls          = ["http://localhost:3000/"] # Placeholder, update as needed
  supported_identity_providers = ["COGNITO"]

}

resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode = "PAY_PER_REQUEST"
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
 point_in_time_recovery {
 enabled = true
 }
 server_side_encryption {
   enabled = true
 }

 tags = {
   Name = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
 }
}



resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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

  tags = {
    Name        = "api-gateway-cloudwatch-role-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
 }

}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
 Effect = "Allow",
 Resource = aws_cloudwatch_log_group.api_gateway.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "/aws/apigateway/${var.project_name}-${var.stack_name}"
  retention_in_days = 30 # Adjust as needed

  tags = {
    Name        = "/aws/apigateway/${var.project_name}-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
 }
}


# Placeholder for Lambda functions (replace with actual function code)
data "archive_file" "lambda_add_item_zip" {
 type        = "zip"
 source_dir  = "./lambda-add-item/" # Replace with your function directory
 output_path = "lambda_add_item.zip"
}

# Placeholder for Lambda functions (replace with actual function code)
data "archive_file" "lambda_get_item_zip" {
 type        = "zip"
 source_dir  = "./lambda-get-item/" # Replace with your function directory
 output_path = "lambda_get_item.zip"
}
# Placeholder for Lambda functions (replace with actual function code)
data "archive_file" "lambda_get_all_items_zip" {
 type        = "zip"
 source_dir  = "./lambda-get-all-items/" # Replace with your function directory
 output_path = "lambda_get_all_items.zip"
}
# Placeholder for Lambda functions (replace with actual function code)
data "archive_file" "lambda_update_item_zip" {
 type        = "zip"
 source_dir  = "./lambda-update-item/" # Replace with your function directory
 output_path = "lambda_update_item.zip"
}
# Placeholder for Lambda functions (replace with actual function code)
data "archive_file" "lambda_complete_item_zip" {
 type        = "zip"
 source_dir  = "./lambda-complete-item/" # Replace with your function directory
 output_path = "lambda_complete_item.zip"
}
# Placeholder for Lambda functions (replace with actual function code)
data "archive_file" "lambda_delete_item_zip" {
 type        = "zip"
 source_dir  = "./lambda-delete-item/" # Replace with your function directory
 output_path = "lambda_delete_item.zip"
}



# (Add Lambda functions resources, IAM roles and policies here)


resource "aws_amplify_app" "main" {
 name       = "${var.project_name}-${var.stack_name}"
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
     postBuild:
       commands:
         - aws s3 sync build/ s3://$BUCKET_NAME
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
 EOF
 access_token = var.github_access_token
 custom_rules = [
 {
   source = "/<*>/"
   target = "/index.html"
   status = "200"
 }
 ]
 tags = {
    Name        = "${var.project_name}-amplify-app-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
 }
}

resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true
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

output "cognito_user_pool_domain" {
 value       = aws_cognito_user_pool_domain.main.domain
 description = "The domain of the Cognito User Pool."
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
 description = "The name of the DynamoDB table."
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
 value       = aws_amplify_app.main.default_domain
 description = "The default domain of the Amplify app."
}

