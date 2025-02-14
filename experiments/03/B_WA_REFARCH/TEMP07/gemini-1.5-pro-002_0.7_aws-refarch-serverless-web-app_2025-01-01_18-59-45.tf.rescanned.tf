terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # allows automatic upgrades to any version greater than or equal to 5.0.0
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
  description = "The name of the stack. Used as a suffix for most resources."
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
  description = "The branch of the GitHub repository to use."
  default     = "master"
}

variable "tags" {
  type = map(string)
  default = {
    Environment = "dev",
    Project     = "todo-app"
  }
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 12 # Increased minimum length
 require_lowercase = true
    require_numbers  = true # Added number requirement
 require_symbols    = true # Added symbol requirement
    require_uppercase = true
  }

 mfa_configuration = "OFF" # Explicitly set MFA to off. Consider enabling MFA for production.
  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = var.tags
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id


  explicit_auth_flows        = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"] # Flows are now explicit
  allowed_oauth_flows                  = ["authorization_code"] # Removed implicit flow
 allowed_oauth_scopes                = ["email", "openid"] # Removed phone scope


  generate_secret                     = false
  callback_urls = ["http://localhost:3000/"] # Placeholder, update with your callback URL
  logout_urls  = ["http://localhost:3000/"] # Placeholder, update with your logout URL
 prevent_user_existence_errors = "ENABLED"

  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Changed to on-demand billing mode
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


 point_in_time_recovery {
 enabled = true
 }
 server_side_encryption {
 enabled = true
 }
  tags = var.tags

}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
 minimum_compression_size = 0
  tags = var.tags
}

resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito_authorizer"
  rest_api_id    = aws_api_gateway_rest_api.main.id
  provider_arns  = [aws_cognito_user_pool.main.arn]
  type           = "COGNITO_USER_POOLS"
}

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api_gateway_cloudwatch_role_${var.stack_name}"

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
 tags = var.tags
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api_gateway_cloudwatch_policy_${var.stack_name}"
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
 Resource = aws_cloudwatch_log_group.api_gateway.arn
      },
    ]
  })
}


resource "aws_cloudwatch_log_group" "api_gateway" {
 name = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
 retention_in_days = 30
}


resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-bucket"


 versioning {
    enabled = true
  }

 logging {
    target_bucket = "${var.application_name}-${var.stack_name}-bucket-logs"
 target_prefix = "log/"
  }


 server_side_encryption_configuration {
 rule {
      apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
      }
 }
  }
  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "main" {
 bucket                  = aws_s3_bucket.main.id
 block_public_acls       = true
 block_public_policy     = true
 ignore_public_acls      = true
 restrict_public_buckets = true
}


resource "aws_iam_role" "amplify_role" {
  name = "amplify_role_${var.stack_name}"
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

 tags = var.tags
}

resource "aws_iam_role_policy" "amplify_policy" {
 name = "amplify_policy_${var.stack_name}"
 role = aws_iam_role.amplify_role.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
 Action = [
          "s3:GetObject",
          "s3:ListBucket"
 ],
        Resource = [
 aws_s3_bucket.main.arn,
          "${aws_s3_bucket.main.arn}/*"
 ]
      }
    ]
 })
}


resource "aws_amplify_app" "main" {
 name      = "${var.application_name}-${var.stack_name}-amplify"
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
  tags = var.tags

 access_token = var.github_access_token
}

resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
 enable_auto_build = true
}


variable "github_access_token" {
 type = string
 description = "Github Access Token"
 sensitive = true
}



resource "aws_lambda_function" "add_item" {
 function_name = "add_item_${var.stack_name}"
  # ... other configuration ...

  tracing_config {
    mode = "Active"
  }
 tags = var.tags
}

# ... other lambda functions ...

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

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.main.id
  description = "The ID of the API Gateway."
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
  description = "The ID of the Amplify App."
}

output "s3_bucket_name" {
  value = aws_s3_bucket.main.bucket
  description = "The name of the S3 bucket."
}
