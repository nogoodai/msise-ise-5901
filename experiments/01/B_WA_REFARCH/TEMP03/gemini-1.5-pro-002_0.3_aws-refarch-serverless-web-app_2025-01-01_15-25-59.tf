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

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  generate_secret                     = false

  callback_urls = ["http://localhost:3000/"] # Replace with your actual callback URLs
  logout_urls   = ["http://localhost:3000/"] # Replace with your actual logout URLs

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5

 attribute {
   name = "cognito-username"
   type = "S"
 }

 attribute {
   name = "id"
   type = "S"
 }

 hash_key  = "cognito-username"
 range_key = "id"

 server_side_encryption {
   enabled = true
 }

 tags = {
   Name        = "todo-table-${var.stack_name}"
   Environment = "prod"
   Project     = var.application_name
 }
}



resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}"
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
     postBuild:
       commands:
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF

 tags = {
   Name        = "${var.application_name}-amplify-app-${var.stack_name}"
   Environment = "prod"
   Project     = var.application_name
 }
}


resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-website"
  acl    = "private"

  tags = {
    Name        = "${var.application_name}-s3-bucket-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true

 tags = {
   Name        = "${var.application_name}-amplify-branch-${var.stack_name}"
   Environment = "prod"
   Project     = var.application_name
 }
}


# Placeholder for API Gateway and Lambda resources (Complex and requires more details for a complete implementation)

output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "s3_bucket_name" {
 value = aws_s3_bucket.main.bucket
}
