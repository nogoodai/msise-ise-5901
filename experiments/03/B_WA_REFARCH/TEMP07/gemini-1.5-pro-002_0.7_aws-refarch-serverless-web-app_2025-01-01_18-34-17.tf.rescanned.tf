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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}


variable "github_personal_access_token" {
  type        = string
  description = "GitHub personal access token with repo access."
  sensitive   = true
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_numbers = true
    require_symbols = true
    require_uppercase = true
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

 mfa_configuration = "OFF"

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  explicit_auth_flows                = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret                     = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  prevent_user_existence_errors      = "ENABLED"


  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST"
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
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"
 minimum_compression_size = 0



  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = var.stack_name
  }
}


resource "aws_s3_bucket" "main" {
  bucket = "${var.stack_name}-app-bucket"
  acl    = "private"


  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm = "AES256"
      }
    }
  }


  tags = {
    Name = var.stack_name
    Environment = "prod"
    Project = var.stack_name
  }

}

resource "aws_amplify_app" "main" {
  name       = var.stack_name
 repository = var.github_repo_url
  access_token = var.github_personal_access_token
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
      - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}/
artifacts:
  baseDirectory: /
  files:
    - '**/*'
EOF

 tags = {
    Name = var.stack_name
    Environment = "prod"
    Project = var.stack_name
  }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
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

  tags = {
    Name        = "${var.stack_name}-api-gateway-cw-role"
    Environment = "prod"
    Project     = var.stack_name
 }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cw-policy"
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
 Resource = aws_cloudwatch_log_group.api_gateway.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
  retention_in_days = 30
}



output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
 description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.main.id
 description = "The ID of the API Gateway."
}
output "s3_bucket_name" {
 value = aws_s3_bucket.main.bucket
 description = "The name of the S3 bucket."
}

resource "aws_accessanalyzer_analyzer" "account" {
 analyzer_name = "account-analyzer-${var.stack_name}"
  type          = "ACCOUNT"
  tags = {
    Name        = "account-analyzer-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

