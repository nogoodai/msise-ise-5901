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
  default     = "us-east-1"
  description = "The AWS region to deploy the infrastructure in."
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name to prefix resources with."
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The branch of the GitHub repository to use."
}

variable "github_access_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token with appropriate permissions."
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  mfa_configuration = "OFF" # Consider enabling MFA for enhanced security

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production" # Replace with your environment
    Project     = "todo-app"    # Replace with your project name
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                     = ["http://localhost:3000/"] # Placeholder - Replace with actual callback URLs
  logout_urls                       = ["http://localhost:3000/"] # Placeholder - Replace with actual logout URLs

    prevent_user_existence_errors = false


}

resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.stack_name}-${random_id.domain_suffix.hex}"
 user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_id" "domain_suffix" {
  byte_length = 4
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PAY_PER_REQUEST" # Use PAY_PER_REQUEST for cost optimization if applicable
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

 point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}




resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-api-gateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-api-gateway-cloudwatch-role"
    Environment = "production"
    Project     = "todo-app"
  }
}



resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*" # Consider restricting this to specific log groups
      },
    ]
  })
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"
 minimum_compression_size = 0

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = "todo-app"
  }
}


resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  rest_api_id    = aws_api_gateway_rest_api.main.id
  provider_arns  = [aws_cognito_user_pool.main.arn]
}




resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })
    tags = {
    Name        = "${var.stack_name}-lambda-role"
    Environment = "production"
    Project     = "todo-app"
  }
}


resource "aws_iam_policy" "lambda_policy" {

  name = "${var.stack_name}-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
 "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:DescribeTable"
        ],
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*" # Consider restricting this to specific log groups
      },
            {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-policy"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}



resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo

  access_token = var.github_access_token


  build_spec = <<-EOT
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci # Use npm ci instead of npm install for deterministic builds
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /dist
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOT

}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}



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
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.main.id
  description = "The ID of the API Gateway."
}


output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
  value       = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}

