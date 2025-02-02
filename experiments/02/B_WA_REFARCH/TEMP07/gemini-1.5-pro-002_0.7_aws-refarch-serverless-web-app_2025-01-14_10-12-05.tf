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
  name = "${var.stack_name}-user-pool"
  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  schema {
    attribute {
      name                     = "email"
      mutable                 = true
      required                 = true
    }

    name = "email"
  }

 username_attributes = ["email"]

  tags = {
    Name        = "${var.stack_name}-cognito-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                                 = "${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  explicit_auth_flows                  = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret                      = false
  prevent_user_existence_errors       = "ENABLED"
  supported_identity_providers         = ["COGNITO"]
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/"] # Placeholder, update with your actual callback URLs
  logout_urls                         = ["http://localhost:3000/"] # Placeholder, update with your actual logout URLs

  tags = {
    Name        = "${var.stack_name}-cognito-user-pool-client"
    Environment = "prod"
    Project     = var.stack_name
  }

}


resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.stack_name}-${random_id.id.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "random_id" "id" {
  byte_length = 4
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
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
    Name        = "${var.stack_name}-dynamodb-table"
    Environment = "prod"
    Project     = var.stack_name
 }
}


resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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
    Name        = "${var.stack_name}-api-gateway-iam-role"
    Environment = "prod"
 Project     = var.stack_name
  }
}



resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_role.id


  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
 Resource = "*"
      },
    ]
  })
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

 tags = {
    Name        = "${var.stack_name}-api-gateway"
    Environment = "prod"
    Project     = var.stack_name
  }
}


resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token

  build_spec = <<-EOT
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
    baseDirectory: build
    files:
      - '**/*'
  EOT

  tags = {
 Name        = "${var.stack_name}-amplify-app"
    Environment = "prod"
 Project     = var.stack_name
 }
}


resource "aws_s3_bucket" "main" {
 bucket = "${var.stack_name}-amplify-bucket-${random_id.id.hex}"
  acl    = "private"

 server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
 }
    }
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.client.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


