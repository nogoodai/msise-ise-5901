terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use a more flexible version constraint
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
  description = "The AWS region to deploy the resources to."
}

variable "stack_name" {
  type    = string
  default = "todo-app"
  description = "The name of the stack."
}

variable "application_name" {
  type    = string
  default = "todo-app"
  description = "The name of the application."

}

variable "github_repo_url" {
  type = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type = string
  default = "master"
  description = "The branch of the GitHub repository to use."

}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 8 # Increased minimum length
    require_lowercase = true
    require_uppercase = true
    require_symbols = true # Require symbols
 require_numbers = true # Require numbers
  }

  mfa_configuration = "OFF" # Explicitly set MFA to OFF

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false


  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
 Environment = "prod"
 Project     = var.application_name
  }
}



resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Use PAY_PER_REQUEST for cost optimization
  #read_capacity  = 5 # Removed since billing mode is on-demand
  #write_capacity = 5 # Removed since billing mode is on-demand

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
    enabled = true # Enable point-in-time recovery
  }

 tags = {
 Name        = "todo-table-${var.stack_name}"
 Environment = "prod"
 Project     = var.application_name
  }
}




resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
 minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
 }
}


resource "aws_api_gateway_authorizer" "cognito" {
 name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
 provider_arns   = [aws_cognito_user_pool.main.arn]
 rest_api_id     = aws_api_gateway_rest_api.main.id

  tags = {
    Name        = "cognito_authorizer"
 Environment = "prod"
    Project     = var.application_name
  }
}



resource "aws_iam_role" "api_gateway_cloudwatch_role" {
 name = "api_gateway_cloudwatch_role_${var.stack_name}"

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
 Name        = "api_gateway_cloudwatch_role_${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
 }
}


resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs" {
 role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}



resource "aws_api_gateway_account" "main" {
 cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
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
 artifacts:
 baseDirectory: /
 files:
      - '**/*'
  cache:
 paths:
 - node_modules/**/*
EOF


  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
 }
}


resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
 enable_auto_build = true
}


resource "aws_iam_role" "lambda_exec_role" {
 name = "lambda_exec_role_${var.stack_name}"
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
 Name = "lambda_exec_role_${var.stack_name}"
    Environment = "prod"
 Project = var.application_name
  }
}



resource "aws_iam_policy" "lambda_dynamodb_policy" {

  name = "lambda_dynamodb_policy_${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
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
 Resource = aws_dynamodb_table.main.arn,
        Effect = "Allow"
      },
      {
 Action = [
 "logs:CreateLogGroup",
            "logs:CreateLogStream",
 "logs:PutLogEvents"
 ],
 Resource = "arn:aws:logs:*:*:*",
 Effect   = "Allow"
 },
 {
 Effect = "Allow",
 Action = [
 "xray:PutTraceSegments",
            "xray:PutTelemetryRecords"
 ],
 Resource = "*"
      }
    ]
 })

  tags = {
    Name        = "lambda_dynamodb_policy_${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
 role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


resource "aws_accessanalyzer_analyzer" "default" {
  analyzer_name = "todo-app-analyzer"
  tags = {
    Name = "todo-app-access-analyzer",
    Environment = "prod",
 Project = "todo-app"
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
