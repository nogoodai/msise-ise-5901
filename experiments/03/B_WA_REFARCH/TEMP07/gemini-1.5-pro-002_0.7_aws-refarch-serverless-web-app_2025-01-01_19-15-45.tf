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
  default = "us-west-2"
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "stack_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

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
 billing_mode = "PROVISIONED"
 read_capacity = 5
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
        Resource = "*"
      },
    ]
  })

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
 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your Github Personal Access Token
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


output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}




