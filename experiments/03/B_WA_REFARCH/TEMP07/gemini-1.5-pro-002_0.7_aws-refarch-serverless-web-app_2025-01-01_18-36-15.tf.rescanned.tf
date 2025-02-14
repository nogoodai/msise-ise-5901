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
  description = "The application's name."
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The GitHub repository for the Amplify app."
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository to use."
  default     = "master"
}

# Cognito
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

 mfa_configuration = "OFF" # Explicitly disable MFA
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev"
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false


}

# DynamoDB
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
   Environment = "dev"
   Project     = var.application_name
 }
}


# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_cw_logs" {
  name = "api-gateway-cw-logs-${var.stack_name}"

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
   Name        = "api-gateway-cw-logs-${var.stack_name}"
   Environment = "dev"
   Project     = var.application_name
 }
}


resource "aws_iam_role_policy" "api_gateway_cw_logs_policy" {
  name = "api-gateway-cw-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_logs.id

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
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "lambda_dynamodb" {
  name = "lambda-dynamodb-${var.stack_name}"
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
   Name        = "lambda-dynamodb-${var.stack_name}"
   Environment = "dev"
   Project     = var.application_name
 }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "lambda-dynamodb-policy-${var.stack_name}"
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
         "dynamodb:BatchGetItem",
         "dynamodb:BatchWriteItem",
         "dynamodb:Query",
         "dynamodb:Scan"
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
       Resource = "*"
     },
     {
       Effect = "Allow",
       Action = [
         "xray:PutTraceSegments",
         "xray:PutTelemetryRecords"
       ],
       Resource = "*"
     },

   ]
 })
  tags = {
    Name        = "lambda-dynamodb-policy-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
 }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
 role       = aws_iam_role.lambda_dynamodb.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"
 minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                  = "cognito_authorizer"
  rest_api_id           = aws_api_gateway_rest_api.main.id
  provider_arns          = [aws_cognito_user_pool.main.arn]
  type                  = "COGNITO_USER_POOLS"
  identity_source       = "method.request.header.Authorization"
}


# Placeholder - Lambda Functions and API Gateway Integration needs actual Lambda code deployment
# Example for one function - Add item
resource "aws_lambda_function" "add_item" {
  function_name = "add_item-${var.stack_name}"
  role          = aws_iam_role.lambda_dynamodb.arn
  handler       = "index.handler" # Placeholder - replace with actual handler
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  # Placeholder - replace with actual code
  filename = "lambda_function.zip" # Replace with actual zip file
  source_code_hash = filebase64sha256("lambda_function.zip") # Replace with actual zip file

 tags = {
   Name        = "add_item-${var.stack_name}"
   Environment = "dev"
   Project     = var.application_name
 }
}


# Amplify
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
  # Placeholder - replace with actual build commands
 build_settings {
   platform = "WEB"
   build_image = "aws/codebuild/standard:5.0" # Replace with appropriate image if needed
   compute_type = "BUILD_GENERAL1_SMALL"  # Adjust compute type as needed
   timeout_in_minutes = 60  # Adjust timeout as needed

   # Example build commands - replace with your actual commands
   pre_build {
     command = "npm install"
   }
   build {
     command = "npm run build"
   }
   post_build {
     command = "aws s3 sync build s3://<your-s3-bucket>" # Replace with your actual deployment command
   }
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

output "api_gateway_url" {
 value       = aws_api_gateway_rest_api.main.id
 description = "The ID of the API Gateway."
}

output "amplify_app_id" {
 value       = aws_amplify_app.main.id
 description = "The ID of the Amplify app."
}
