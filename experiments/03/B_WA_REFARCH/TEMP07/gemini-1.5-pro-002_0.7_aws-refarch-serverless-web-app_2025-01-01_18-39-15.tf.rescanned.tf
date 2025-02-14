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
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The name of the application."
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token with repo scope."
  sensitive   = true
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length     = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "SMS_TEXT_MESSAGE" # Enabling MFA
  sms_configuration {
    sns_caller_arn = aws_iam_role.cognito_sns_role.arn
  }
 tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev"
    Project     = var.application_name
  }
}


resource "aws_iam_role" "cognito_sns_role" {
  name               = "cognito-sns-role"
  assume_role_policy = data.aws_iam_policy_document.cognito_sns_assume_role_policy.json

  tags = {
    Name        = "cognito-sns-role"
    Environment = "dev"
    Project     = var.application_name
  }
}

data "aws_iam_policy_document" "cognito_sns_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "cognito.amazonaws.com",
      ]
    }
  }
}



resource "aws_cognito_user_pool_client" "main" {
  name             = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id      = aws_cognito_user_pool.main.id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  generate_secret                     = false
  prevent_user_existence_errors      = "ENABLED" # Prevent User Existence Errors

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-domain"
    Environment = "dev"
    Project     = var.application_name
  }
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
    Environment = "dev"
    Project     = var.application_name
  }
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"

 minimum_compression_size = 0

 tags = {
 Name = "${var.application_name}-${var.stack_name}-api"
 Environment = "dev"
 Project = var.application_name
 }
}




resource "aws_amplify_app" "main" {
 name           = "${var.application_name}-${var.stack_name}-amplify-app"
 repository     = var.github_repo
 access_token   = var.github_access_token
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
     postBuild:
       commands:
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
 EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
 Environment = "dev"
 Project     = var.application_name
  }
}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
 enable_auto_build = true

  tags = {
 Name = "${var.application_name}-${var.stack_name}-amplify-branch"
 Environment = "dev"
 Project = var.application_name
 }
}


resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-role"

  assume_policy = jsonencode({
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
 Name = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-role"
 Environment = "dev"
 Project = var.application_name
 }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
 name = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-policy"
  role = aws_iam_role.api_gateway_cloudwatch_logs_role.id

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

 tags = {
 Name = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-policy"
 Environment = "dev"
 Project = var.application_name
 }
}


resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
  retention_in_days = 30
 tags = {
 Name = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
 Environment = "dev"
 Project = var.application_name
 }

}



resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-s3-bucket"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
 sse_algorithm = "AES256"
      }
    }
  }

  versioning {
    enabled = true
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-s3-bucket"
 Environment = "dev"
 Project     = var.application_name
  }
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

output "s3_bucket_name" {
 value = aws_s3_bucket.main.bucket
 description = "The name of the s3 bucket."
}

output "s3_bucket_arn" {
 value = aws_s3_bucket.main.arn
 description = "The ARN of the s3 bucket."
}


