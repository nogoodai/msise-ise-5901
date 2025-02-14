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
  description = "The AWS region to deploy the resources to."
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack."
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application."

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

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }


  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
  mfa_configuration = "OFF" # Explicitly set MFA to OFF
 tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "production" # Example environment tag
    Project     = "todo-app" # Example project tag
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Replace with your callback URL
  logout_urls                         = ["http://localhost:3000/"] # Replace with your logout URL
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

 point_in_time_recovery {
    enabled = true
  }

 tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
 Project = "todo-app"
 }
}



resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"

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
    Name = "api-gateway-cw-role-${var.stack_name}"
 Environment = "production"
 Project = "todo-app"
  }
}


resource "aws_iam_role_policy" "api_gateway_cw_policy" {
 name = "api-gateway-cw-policy-${var.stack_name}"
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
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}

resource "aws_apigatewayv2_api" "main" {
  name         = "${var.application_name}-${var.stack_name}-api"
  protocol_type = "HTTP"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
 Environment = "production"
 Project     = "todo-app"
  }
}

resource "aws_lambda_function" "add_item" {
 filename      = "add_item.zip"
 function_name = "add_item-${var.stack_name}"
 handler       = "index.handler"
 runtime = "nodejs12.x"
 role          = aws_iam_role.lambda_dynamodb_role.arn
 memory_size = 1024
 timeout      = 60
 tracing_config {
   mode = "Active"
 }

 environment {
    variables = {
 TABLE_NAME = aws_dynamodb_table.main.name
    }
 }

 tags = {
        Name = "add_item-${var.stack_name}"
 Environment = "production"
 Project = "todo-app"
 }
}

resource "aws_iam_role" "lambda_dynamodb_role" {
  name = "lambda-dynamodb-role-${var.stack_name}"

 assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
 })

  tags = {
 Name = "lambda-dynamodb-role-${var.stack_name}"
 Environment = "production"
 Project = "todo-app"
 }
}


resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy-${var.stack_name}"
 role = aws_iam_role.lambda_dynamodb_role.id

  policy = jsonencode({
 Version = "2012-10-17",
 Statement = [
      {
        Action = [
 "dynamodb:GetItem",
          "dynamodb:PutItem",
 "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
 "dynamodb:Scan",
 "dynamodb:Query",
          "dynamodb:BatchWriteItem",
          "dynamodb:BatchGetItem",
 "dynamodb:DescribeTable"
 ],
        Effect   = "Allow",
 Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
 "cloudwatch:PutMetricData"
 ],
 Effect = "Allow",
 Resource = "*"
      }
    ]
 })
}



resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo
 build_spec = <<EOF
 version: 0.1
 frontend:
 phases:
   install:
     commands:
       - npm install
   build:
     commands:
       - npm run build
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF
}

resource "aws_amplify_branch" "main" {
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
 description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
  value       = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}
