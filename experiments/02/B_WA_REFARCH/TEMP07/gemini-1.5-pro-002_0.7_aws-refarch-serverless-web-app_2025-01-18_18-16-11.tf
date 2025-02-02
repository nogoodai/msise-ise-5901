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
  type    = string
  default = "us-west-2"
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


resource "aws_cognito_user_pool" "pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000"] # Placeholder, update with actual callback URL
  logout_urls          = ["http://localhost:3000/signout"] # Placeholder, update with actual logout URL
  supported_identity_providers = ["COGNITO"]
}


resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_dynamodb_table" "todo_table" {
 name         = "todo-table-${var.stack_name}"
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
   Name        = "todo-table-${var.stack_name}"
   Environment = var.stack_name
   Project     = var.application_name
 }
}


resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Sid    = "",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_cw_policy" {
 name = "api-gateway-cw-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_role.id
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents",
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}



resource "aws_amplify_app" "app" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url
  platform   = "WEB"

 build_spec = <<EOF
version: 0.1
frontend:
 phases:
   preBuild:
     commands:
       - yarn install
   build:
     commands:
       - yarn build
   postBuild:
     commands:
       - aws s3 sync build s3://${aws_s3_bucket.amplify_bucket.bucket}
artifacts:
  baseDirectory: /
  files:
    - '**/*'
EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_s3_bucket" "amplify_bucket" {
  bucket = "${var.application_name}-${var.stack_name}-amplify-bucket"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}



resource "aws_amplify_branch" "master" {
 app_id   = aws_amplify_app.app.id
 branch_name = var.github_branch
 enable_auto_build = true

 tags = {
   Name        = "${var.application_name}-${var.stack_name}-amplify-branch"
   Environment = var.stack_name
   Project     = var.application_name
 }
}


# Placeholder resources, these need more specific implementation based on the actual function needs

resource "aws_lambda_function" "example_function" { # Example, replace with actual functions
 filename      = "lambda_function.zip" # Placeholder, replace with actual zip file
 function_name = "example-function-${var.stack_name}"
 handler       = "index.handler"
 runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60
  role = aws_iam_role.lambda_exec_role.arn # Replace with actual lambda role ARN



  tags = {
    Name        = "example-function-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role" "lambda_exec_role" { # Example, refine with specific permissions
  name = "lambda-exec-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Sid    = "",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}


output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.pool.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.client.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.todo_table.name
}


