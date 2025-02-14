# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "environment" {
  type        = string
  default     = "example"
  description = "Environment name"
}

variable "project" {
  type        = string
  default     = "example"
  description = "Project name"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "example" {
  name                     = var.environment
  username_attributes      = ["email"]
  email_verification       = true
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
  mfa_configuration        = "OFF"
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "example" {
  name                 = var.environment
  user_pool_id         = aws_cognito_user_pool.example.id
  generate_secret      = false
  allowed_oauth_flows  = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "example" {
  domain       = var.environment
  user_pool_id = aws_cognito_user_pool.example.id
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "example" {
  name           = var.environment
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
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
  table_status = "ACTIVE"
  billing_mode  = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  server_side_encryption {
    enabled = true
  }
  point_in_time_recovery {
    enabled = true
  }
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "example" {
  name        = var.environment
  description = "Example API"
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_resource" "example" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_rest_api.example.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "example_get" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.example.id
  api_key_required = true
}

resource "aws_api_gateway_method" "example_post" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.example.id
  api_key_required = true
}

resource "aws_api_gateway_method" "example_put" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.example.id
  api_key_required = true
}

resource "aws_api_gateway_method" "example_delete" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.example.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "example_get" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example_get.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:example-lambda/invocations"
}

resource "aws_api_gateway_integration" "example_post" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:example-lambda/invocations"
}

resource "aws_api_gateway_integration" "example_put" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example_put.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:example-lambda/invocations"
}

resource "aws_api_gateway_integration" "example_delete" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  resource_id = aws_api_gateway_resource.example.id
  http_method = aws_api_gateway_method.example_delete.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:example-lambda/invocations"
}

resource "aws_api_gateway_authorizer" "example" {
  name           = var.environment
  rest_api_id    = aws_api_gateway_rest_api.example.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.example.arn]
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_deployment" "example" {
  depends_on = [aws_api_gateway_integration.example_get, aws_api_gateway_integration.example_post, aws_api_gateway_integration.example_put, aws_api_gateway_integration.example_delete]
  rest_api_id = aws_api_gateway_rest_api.example.id
  stage_name  = "prod"
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_usage_plan" "example" {
  name         = var.environment
  description  = "Example usage plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.example.id
    stage  = aws_api_gateway_deployment.example.stage_name
  }
  quota {
    limit  = 5000
    offset = 100
    period  = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

# Lambda Functions
resource "aws_lambda_function" "example" {
  filename      = "lambda_function_payload.zip"
  function_name = var.environment
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.example_lambda.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_permission" "example" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.example.execution_arn}/*/*"
}

# Amplify App
resource "aws_amplify_app" "example" {
  name        = var.environment
  description = "Example Amplify app"
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_amplify_branch" "example" {
  app_id      = aws_amplify_app.example.id
  branch_name = "master"
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_amplify_webhook" "example" {
  app_id      = aws_amplify_app.example.id
  branch_name = aws_amplify_branch.example.branch_name
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "example_api_gateway" {
  name        = "${var.environment}-api-gateway-role"
  description = "Example API Gateway role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_policy" "example_api_gateway" {
  name        = "${var.environment}-api-gateway-policy"
  description = "Example API Gateway policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "example_api_gateway" {
  role       = aws_iam_role.example_api_gateway.name
  policy_arn = aws_iam_policy.example_api_gateway.arn
}

resource "aws_iam_role" "example_amplify" {
  name        = "${var.environment}-amplify-role"
  description = "Example Amplify role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_policy" "example_amplify" {
  name        = "${var.environment}-amplify-policy"
  description = "Example Amplify policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateWebhook",
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "example_amplify" {
  role       = aws_iam_role.example_amplify.name
  policy_arn = aws_iam_policy.example_amplify.arn
}

resource "aws_iam_role" "example_lambda" {
  name        = "${var.environment}-lambda-role"
  description = "Example Lambda role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_policy" "example_lambda" {
  name        = "${var.environment}-lambda-policy"
  description = "Example Lambda policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.example.arn
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "example_lambda" {
  role       = aws_iam_role.example_lambda.name
  policy_arn = aws_iam_policy.example_lambda.arn
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.example.id
  description = "The ID of the Cognito User Pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.example.id
  description = "The ID of the Cognito User Pool Client"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.example.id
  description = "The ID of the API Gateway"
}

output "lambda_function_arn" {
  value       = aws_lambda_function.example.arn
  description = "The ARN of the Lambda Function"
}

output "amplify_app_id" {
  value       = aws_amplify_app.example.id
  description = "The ID of the Amplify App"
}

output "amplify_branch_name" {
  value       = aws_amplify_branch.example.branch_name
  description = "The name of the Amplify Branch"
}
