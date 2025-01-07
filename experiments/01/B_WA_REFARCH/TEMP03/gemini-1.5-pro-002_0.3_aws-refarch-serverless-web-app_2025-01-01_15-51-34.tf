terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider aws {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
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
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project}-user-pool-${var.environment}"
  username_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.project}-user-pool-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project}-user-pool-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls = ["http://localhost:3000/"] # Replace with your actual callback URLs
  logout_urls   = ["http://localhost:3000/"] # Replace with your actual logout URLs

  tags = {
    Name        = "${var.project}-user-pool-client-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
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
   Name        = "todo-table-${var.stack_name}"
   Environment = var.environment
   Project     = var.project
 }
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project}-api-${var.environment}"
  description = "API Gateway for ${var.project}"

 tags = {
   Name        = "${var.project}-api-${var.environment}"
   Environment = var.environment
   Project     = var.project
 }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.project}-api-gateway-cw-role-${var.environment}"

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
    Name        = "${var.project}-api-gateway-cw-role-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "${var.project}-api-gateway-cw-policy-${var.environment}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}

resource "aws_api_gateway_account" "main" {
 cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
}


resource "aws_amplify_app" "main" {
 name       = "${var.project}-amplify-app-${var.environment}"
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token

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
    Name        = "${var.project}-amplify-app-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket" "main" {
  bucket = "${var.project}-amplify-bucket-${var.environment}"
  acl    = "private"

  tags = {
    Name        = "${var.project}-amplify-bucket-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
  enable_auto_build = true

  tags = {
    Name        = "${var.project}-amplify-branch-${var.environment}"
    Environment = var.environment
    Project     = var.project
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
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

output "s3_bucket_name" {
  value = aws_s3_bucket.main.bucket
}
