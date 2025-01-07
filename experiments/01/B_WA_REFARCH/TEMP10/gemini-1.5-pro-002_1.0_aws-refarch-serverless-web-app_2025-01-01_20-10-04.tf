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

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type = string
  default = "todo-app"
}

variable "stack_name" {
  type = string
  default = "todo-app-stack"

}

variable "github_repo" {
  type = string
  default = "your-github-repo"

}
variable "github_branch" {
  type = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.environment}"
  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"
  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
    temporary_password_validity_days = 7
  }
  schema {
    attribute_data_type = "String"
    developer_only_attribute = false
    mutable = true
    name = "email"
    required = true
  }
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.project_name}-user-pool-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.project_name}-user-pool-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id


 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Replace with your callback URLs
  generate_secret = false
  refresh_token_validity = 30
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "${var.project_name}-user-pool-client-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
 read_capacity = 5
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
    Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.project_name}-api-gateway-cw-role-${var.environment}"

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
    Name        = "${var.project_name}-api-gateway-cw-role-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }

}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.project_name}-api-gateway-cw-policy-${var.environment}"
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
        Effect = "Allow",
 Resource = "*"
      },
    ]
  })
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api-${var.environment}"
 description = "API Gateway for ${var.project_name}"

  tags = {
    Name        = "${var.project_name}-api-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_amplify_app" "main" {
  name       = "${var.project_name}-amplify-app-${var.environment}"
 repository = var.github_repo
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token
 build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF


  tags = {
    Name        = "${var.project_name}-amplify-app-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
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


