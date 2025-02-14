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
  description = "The application name to deploy the resources in."
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

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
 mfa_configuration = "OFF"
  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes              = ["email", "phone", "openid"]
  callback_urls                     = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls                       = ["http://localhost:3000/"] # Replace with your logout URLs
  supported_identity_providers      = ["COGNITO"]
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

 point_in_time_recovery {
    enabled = true
  }
 tags = {
    Name        = "todo-table-${var.stack_name}"
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
      },
    ]
  })
  tags = {
    Name        = "api-gateway-cloudwatch-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
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
     }
   ]
 })
}


resource "aws_apigatewayv2_api" "main" {
 name = "todo-api-${var.stack_name}"
 protocol_type = "HTTP"
 tags = {
    Name        = "todo-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-website"
  acl    = "private"

 versioning {
    enabled = true
 }
 logging {
    target_bucket = "s3-logging-${var.stack_name}" # Replace with your logging bucket name
 target_prefix = "log/"
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-website"
    Environment = "prod"
    Project     = var.application_name
  }


}


resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

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
 tags = {
    Name        = "amplify-role-${var.stack_name}"
 Environment = "prod"
 Project     = var.application_name
 }
}

resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo_url
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

  iam_service_role_arn = aws_iam_role.amplify_role.arn
}


resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
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

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
 description = "The name of the DynamoDB table."
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_api.main.api_endpoint
 description = "The URL of the API Gateway."
}

output "amplify_app_id" {
 value       = aws_amplify_app.main.id
 description = "The ID of the Amplify App."
}
