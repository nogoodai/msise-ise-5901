# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "stack_name" {
  type        = string
  default     = "serverless-web-application"
  description = "The name of the stack"
}

variable "application_name" {
  type        = string
  default     = "todo-application"
  description = "The name of the application"
}

variable "github_repository" {
  type        = string
  default     = "https://github.com/username/todo-application-frontend.git"
  description = "The URL of the GitHub repository"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The name of the GitHub branch"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "The GitHub token for authentication"
}

# Create Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                     = "${var.stack_name}-user-pool"
  alias_attributes         = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  sms_verification_message  = "Your verification code is {####}."
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_symbols   = false
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

# Create Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "dynamodb_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
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
}

# Create API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.stack_name}-api-gateway"
  description = "API Gateway for ${var.stack_name}"
}

# Create API Gateway Authorizer
resource "aws_api_gateway_authorizer" "authorizer" {
  name          = "${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# Create API Gateway Resource and Method
resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

# Create API Gateway Integration
resource "aws_api_gateway_integration" "integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.lambda_function.arn}/invocations"
}

# Create API Gateway Deployment
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

# Create API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name}"
}

# Create API Gateway Usage Plan Key
resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
  key_type      = "API_KEY"
  key          = aws_api_gateway_api_key.api_key.id
}

# Create API Gateway API Key
resource "aws_api_gateway_api_key" "api_key" {
  name        = "${var.stack_name}-api-key"
  description = "API key for ${var.stack_name}"
}

# Create Lambda Function
resource "aws_lambda_function" "lambda_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-lambda-function"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.dynamodb_table.name
    }
  }
}

# Create Lambda Function Policies
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for ${var.stack_name} lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.dynamodb_table.arn
        Effect    = "Allow"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
    ]
  })
}

# Create Lambda Function Role
resource "aws_iam_role" "lambda_role" {
  name        = "${var.stack_name}-lambda-role"
  description = "Role for ${var.stack_name} lambda function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      },
    ]
  })
}

# Attach Lambda Function Policy to Lambda Function Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Create Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = "${var.stack_name}-amplify-app"
  description = "Amplify app for ${var.stack_name}"
}

# Create Amplify Branch
resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = var.github_branch
}

# Create Amplify GitHub Token
resource "aws_amplify_github_token" "github_token" {
  app_id      = aws_amplify_app.amplify_app.id
  token       = var.github_token
}

# Create IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "Role for ${var.stack_name} API Gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      },
    ]
  })
}

# Create IAM Policy for API Gateway
resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "Policy for ${var.stack_name} API Gateway"

  policy = jsonencode({
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
    ]
  })
}

# Attach IAM Policy to IAM Role for API Gateway
resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

# Create IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name        = "${var.stack_name}-amplify-role"
  description = "Role for ${var.stack_name} Amplify"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      },
    ]
  })
}

# Create IAM Policy for Amplify
resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Policy for ${var.stack_name} Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Resource = "*"
        Effect    = "Allow"
      },
    ]
  })
}

# Attach IAM Policy to IAM Role for Amplify
resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Output critical information
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.lambda_function.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.amplify_branch.branch_name
}
