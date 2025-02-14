provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "The environment of the stack"
}

variable "github_repository" {
  type        = string
  default     = "https://github.com/my-repo/my-repo.git"
  description = "The GitHub repository URL"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "my-user-pool-${var.stack_name}"
  alias_attributes   = ["email"]
  username_attributes = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
  mfa_configuration = "OFF"
  tags = {
    Name        = "my-user-pool-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "my-user-pool-client-${var.stack_name}"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls      = ["https://example.com/callback"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain               = "auth-${var.stack_name}.example.com"
  user_pool_id         = aws_cognito_user_pool.this.id
  certificate_arn      = aws_acm_certificate.this.arn
}

# ACM Certificate
resource "aws_acm_certificate" "this" {
  domain_name       = "auth-${var.stack_name}.example.com"
  validation_method = "DNS"
  subject_alternative_names = []
  tags = {
    Name        = "my-acm-certificate-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
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
  server_side_encryption {
    enabled = true
  }
  point_in_time_recovery {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "my-api-${var.stack_name}"
  description = "My API"
  minimum_compression_size = 0
  tags = {
    Name        = "my-api-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "my-authorizer-${var.stack_name}"
  rest_api_id    = aws_api_gateway_rest_api.this.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  tags = {
    Name        = "my-authorizer-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_method.post, aws_api_gateway_method.get]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
  tags = {
    Name        = "my-deployment-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  name         = "my-usage-plan-${var.stack_name}"
  description  = "My usage plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_deployment.this.stage_name
  }
  quota {
    limit  = 5000
    offset = 2
    period  = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
  tags = {
    Name        = "my-usage-plan-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "add-item-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "get-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "get-item-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "get-all-items-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "get-all-items-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "update-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "update-item-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "complete-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "complete-item-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "delete-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "delete-item-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

# API Gateway Integration
resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.add_item.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.get_item.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "my-app-${var.stack_name}"
  description = "My app"
  tags = {
    Name        = "my-app-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
}

resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment = "prod"
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec" {
  name        = "lambda-exec-${var.stack_name}"
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
      }
    ]
  })
  tags = {
    Name        = "lambda-exec-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_iam_policy" "lambda_exec" {
  name        = "lambda-exec-policy-${var.stack_name}"
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
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
    ]
  })
  tags = {
    Name        = "lambda-exec-policy-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_role" "api_gateway_exec" {
  name        = "api-gateway-exec-${var.stack_name}"
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
      }
    ]
  })
  tags = {
    Name        = "api-gateway-exec-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_iam_policy" "api_gateway_exec" {
  name        = "api-gateway-exec-policy-${var.stack_name}"
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
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
  tags = {
    Name        = "api-gateway-exec-policy-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "amplify-exec-${var.stack_name}"
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
      }
    ]
  })
  tags = {
    Name        = "amplify-exec-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_iam_policy" "amplify_exec" {
  name        = "amplify-exec-policy-${var.stack_name}"
  description = "Amplify execution policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:UpdateApp",
          "amplify:DeleteApp",
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.this.arn
      },
    ]
  })
  tags = {
    Name        = "amplify-exec-policy-${var.stack_name}"
    Environment  = var.environment
    Project      = "my-project"
  }
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "The ID of the Cognito User Pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.this.id
  description = "The ID of the Cognito User Pool Client"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.this.id
  description = "The ID of the API Gateway"
}

output "api_gateway_deployment_id" {
  value       = aws_api_gateway_deployment.this.id
  description = "The ID of the API Gateway Deployment"
}

output "lambda_function_arns" {
  value       = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn,
  ]
  description = "The ARNs of the Lambda Functions"
}

output "amplify_app_id" {
  value       = aws_amplify_app.this.id
  description = "The ID of the Amplify App"
}

output "amplify_branch_name" {
  value       = aws_amplify_branch.this.branch_name
  description = "The name of the Amplify Branch"
}
