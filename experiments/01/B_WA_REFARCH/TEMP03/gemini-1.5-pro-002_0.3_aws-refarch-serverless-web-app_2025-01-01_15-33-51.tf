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
  default = "us-east-1"
}

variable "stack_name" {
  default = "todo-app"
}

variable "application_name" {
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  email_verification_message = "Your verification code is: {####}"
  email_verification_subject = "Verify your email"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  tags = {
    Name      = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  tags = {
    Name      = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name      = "${var.application_name}-${var.stack_name}-user-pool-domain"
    Environment = "prod"
    Project     = var.application_name
  }
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

 tags = {
    Name      = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
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
      }
    ]
  })

  tags = {
    Name      = "api-gateway-cloudwatch-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
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
     }
   ]
 })

 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
}


resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}


resource "aws_apigatewayv2_api" "main" {
 name = "${var.application_name}-${var.stack_name}-api"
 protocol_type = "HTTP"

 tags = {
    Name      = "${var.application_name}-${var.stack_name}-api"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
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
      cache:
        paths:
          - node_modules/**/*
  EOT

  tags = {
    Name      = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true

 tags = {
    Name      = "${var.application_name}-${var.stack_name}-amplify-branch"
    Environment = "prod"
    Project     = var.application_name
  }
}


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
 value = aws_apigatewayv2_api.main.id
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}
