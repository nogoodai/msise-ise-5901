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

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
}


resource "aws_cognito_user_pool_domain" "main" {
 domain      = "${var.stack_name}-${random_id.main.hex}"
 user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_id" "main" {
  byte_length = 8
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

resource "aws_iam_role" "api_gateway_cw_role" {
  name = "${var.stack_name}-api-gateway-cw-role"

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


resource "aws_iam_role_policy" "api_gateway_cw_policy" {
  name = "${var.stack_name}-api-gateway-cw-policy"
  role = aws_iam_role.api_gateway_cw_role.id

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
      }
    ]
  })
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
 description = "API Gateway for ${var.stack_name}"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
 provider_arns = [aws_cognito_user_pool.main.arn]
 rest_api_id   = aws_api_gateway_rest_api.main.id
}


resource "aws_amplify_app" "main" {
  name       = var.stack_name
 repository = var.github_repo
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
 artifacts:
  baseDirectory: build
  files:
    - '**/*'
 EOT
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
 Principal = {
 Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" # Replace with least privilege policy
  role       = aws_iam_role.amplify_role.name
}
