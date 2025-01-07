terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

# Variables
variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

variable "region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "my-user-pool"
  username_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  # Auto-verify email
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "my-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]

  # Auth scopes
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5

  # Attribute definitions
  attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  # Key schema
  key_schema = [
    {
      attribute_name = "cognito-username"
      key_type       = "HASH"
    },
    {
      attribute_name = "id"
      key_type       = "RANGE"
    }
  ]

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "my-api"
  description = "My REST API"
}

resource "aws_api_gateway_resource" "this" {
  path_part   = "item"
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "my-authorizer"
  rest_api_id    = aws_api_gateway_rest_api.this.id
  type           = "COGNITO_USER_POOLS"
  provider_arns  = [aws_cognito_user_pool.this.arn]
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "this" {
  depends_on  = [aws_api_gateway_method.get_item, aws_api_gateway_method.post_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "this" {
  name        = "my-usage-plan"
  description = "My usage plan"

  # Quota settings
  quota {
    limit  = 5000
    offset = 0
    period = "DAY"
  }

  # Throttle settings
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Function
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:123456789012:function:${aws_lambda_function.add_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:123456789012:function:${aws_lambda_function.get_item.function_name}/invocations"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "my-app"
  description = "My Amplify app"

  # Build spec
  build_spec = <<-EOT
    version: 1.0
    phases:
      install:
        commands:
          - npm install
      build:
        commands:
          - npm run build
    artifacts:
      baseDirectory: dist
      files:
        - '**/*'
  EOT

  # Source
  source {
    type = "GitHub"
    owner = "username"
    repo  = "repo-name"
    branch = "master"
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "api-gateway-exec"
  description = "API Gateway execution role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "api_gateway_exec" {
  name        = "api-gateway-exec"
  description = "API Gateway execution policy"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "lambda-exec"
  description = "Lambda execution role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_exec" {
  name        = "lambda-exec"
  description = "Lambda execution policy"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "amplify-exec"
  description = "Amplify execution role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "amplify_exec" {
  name        = "amplify-exec"
  description = "Amplify execution policy"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:UpdateApp",
          "amplify:DeleteApp",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "The ID of the Cognito user pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.this.id
  description = "The ID of the Cognito user pool client"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.this.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.this.id
  description = "The ID of the API Gateway"
}

output "lambda_function_name" {
  value       = aws_lambda_function.add_item.function_name
  description = "The name of the Lambda function"
}

output "amplify_app_id" {
  value       = aws_amplify_app.this.id
  description = "The ID of the Amplify app"
}
