# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

# Define variables
variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application"
}

variable "stack_name" {
  type        = string
  default     = "dev"
  description = "The name of the stack"
}

variable "github_repository" {
  type        = string
  default     = "https://github.com/username/todo-app-frontend.git"
  description = "The GitHub repository URL"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch name"
}

# Create a Cognito User Pool
resource "aws_cognito_user_pool" "todo_app" {
  name                = "${var.application_name}-${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  mfa_configuration = "OFF"
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create a Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls       = ["https://${var.application_name}-${var.stack_name}.auth.us-west-2.amazoncognito.com/oauth2/idpresponse"]
}

# Create a Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_app.id
}

# Create a DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
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
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create an API Gateway REST API
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "Todo API"
  minimum_compression_size = 0
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create an API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  deployment_id = aws_api_gateway_deployment.todo_api.id
  xray_tracing_enabled = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format          = "{\"requestId\":\"$context.requestId\",\"ip\":\"$context.identity.sourceIp\",\"caller\":\"$context.identity.caller\",\"user\":\"$context.identity.user\",\"requestTime\":\"$context.requestTime\",\"httpMethod\":\"$context.httpMethod\",\"resourcePath\":\"$context.resourcePath\",\"status\":\"$context.status\",\"protocol\":\"$context.protocol\",\"responseLength\":\"$context.responseLength\"}"
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-stage"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create an API Gateway Deployment
resource "aws_api_gateway_deployment" "todo_api" {
  depends_on = [aws_api_gateway_integration.add_item]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
}

# Create an API Gateway Integration
resource "aws_api_gateway_integration" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.add_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

# Create an API Gateway Resource
resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

# Create an API Gateway Method
resource "aws_api_gateway_method" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
  api_key_required = true
}

# Create an API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name           = "${var.application_name}-${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app.arn]
}

# Create a Lambda Function
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-add-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create an IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name        = "${var.application_name}-${var.stack_name}-lambda-execution-role"
  description = "Execution role for lambda functions"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-execution-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create an IAM Policy for Lambda
resource "aws_iam_policy" "lambda" {
  name        = "${var.application_name}-${var.stack_name}-lambda-policy"
  description = "Policy for lambda functions"
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
        Resource = aws_dynamodb_table.todo_table.arn
      },
    ]
  })
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Attach the IAM Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# Create an IAM Role for API Gateway
resource "aws_iam_role" "api_gateway" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-execution-role"
  description = "Execution role for API Gateway"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-execution-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create an IAM Policy for API Gateway
resource "aws_iam_policy" "api_gateway" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
  description = "Policy for API Gateway"
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
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Attach the IAM Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

# Create a CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "${var.application_name}-${var.stack_name}-api-gateway-logs"
  retention_in_days = 30
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-logs"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create an Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.application_name}-${var.stack_name}"
  description = "Todo app"
  platform   = "Web"
  build_spec = <<-EOT
    version: 0.1.0
    frontend:
      phases:
        preBuild:
          commands:
            - npm install
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: dist
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT
  tags = {
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create an Amplify Branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

# Create an Amplify Environment
resource "aws_amplify_environment" "prod" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "prod"
}

# Create an IAM Role for Amplify
resource "aws_iam_role" "amplify" {
  name        = "${var.application_name}-${var.stack_name}-amplify-execution-role"
  description = "Execution role for Amplify"
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
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-execution-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Create an IAM Policy for Amplify
resource "aws_iam_policy" "amplify" {
  name        = "${var.application_name}-${var.stack_name}-amplify-policy"
  description = "Policy for Amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetEnvironment",
          "amplify:UpdateApp",
          "amplify:UpdateBranch",
          "amplify:UpdateEnvironment",
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.todo_app.arn
      },
    ]
  })
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Attach the IAM Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

# Create outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.todo_app.id
  description = "The ID of the Cognito User Pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.todo_app.id
  description = "The ID of the Cognito User Pool Client"
}

output "api_gateway_rest_api_id" {
  value       = aws_api_gateway_rest_api.todo_api.id
  description = "The ID of the API Gateway REST API"
}

output "api_gateway_deployment_id" {
  value       = aws_api_gateway_deployment.todo_api.id
  description = "The ID of the API Gateway Deployment"
}

output "lambda_function_names" {
  value       = [
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.update_item.function_name,
    aws_lambda_function.complete_item.function_name,
    aws_lambda_function.delete_item.function_name,
  ]
  description = "The names of the Lambda functions"
}

output "amplify_app_id" {
  value       = aws_amplify_app.todo_app.id
  description = "The ID of the Amplify App"
}

output "amplify_branch_name" {
  value       = aws_amplify_branch.master.branch_name
  description = "The name of the Amplify Branch"
}
