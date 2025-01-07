# Configure the AWS Provider
terraform {
  required_version = ">= 1.2.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.53.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.2.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "project_name" {
  type        = string
  default     = "serverless-web-app"
  description = "The name of the project"
}

variable "stack_name" {
  type        = string
  default     = "prod"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  description = "The GitHub repository URL for the frontend code"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch to use for deployment"
}

# Create Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.project_name}-user-pool"
  alias_attributes   = ["email"]
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  username_attributes = ["email"]
  username_configuration {
    case_sensitivity = "CaseInsensitive"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.project_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = [
    "email",
    "phone",
    "openid",
  ]
}

# Create Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain               = "${var.project_name}.${var.stack_name}"
  user_pool_id         = aws_cognito_user_pool.this.id
  depends_on          = [aws_cognito_user_pool.this]
}

# Create DynamoDB Table
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
  local_secondary_index {
    name               = "id-index"
    range_key          = "id"
    projection_type    = "INCLUDE"
    non_key_attributes = ["id"]
  }
  server_side_encryption {
    enabled = true
  }
  depends_on = [aws_cognito_user_pool.this]
  lifecycle {
    create_before_destroy = true
  }
}

# Create IAM Role for API Gateway
resource "aws_iam_role" "api_gateway" {
  name        = "${var.project_name}-api-gateway-role"
  description = "Role for API Gateway to write logs to CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

# Create IAM Policy for API Gateway
resource "aws_iam_policy" "api_gateway" {
  name        = "${var.project_name}-api-gateway-policy"
  description = "Policy for API Gateway to write logs to CloudWatch"

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

# Attach IAM Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

# Create API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = var.project_name
  description = "API Gateway for serverless web application"
}

# Create API Gateway Resource and Method
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
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

# Create API Gateway Authorizer
resource "aws_api_gateway_authorizer" "this" {
  name           = var.project_name
  type           = "COGNITO_USER_POOLS"
  provider_arns  = [aws_cognito_user_pool.this.arn]
  rest_api_id    = aws_api_gateway_rest_api.this.id
}

# Create API Gateway Stage
resource "aws_api_gateway_stage" "this" {
  stage_name    = var.stack_name
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
}

# Create API Gateway Deployment
resource "aws_api_gateway_deployment" "this" {
  depends_on  = [aws_api_gateway_method.post, aws_api_gateway_method.get]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name   = var.stack_name
}

# Create Lambda Function
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
}

# Create IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name        = "${var.project_name}-lambda-role"
  description = "Role for Lambda function to interact with DynamoDB"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

# Create IAM Policy for Lambda
resource "aws_iam_policy" "lambda" {
  name        = "${var.project_name}-lambda-policy"
  description = "Policy for Lambda function to interact with DynamoDB"

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
        Resource = aws_dynamodb_table.this.arn
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

# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# Create API Gateway Integration
resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

# Create Amplify App
resource "aws_amplify_app" "this" {
  name        = var.project_name
  description = "Amplify app for serverless web application"
  platform    = "WEB"
}

# Create Amplify Branch
resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

# Create Amplify Environment
resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  environment = "prod"
}

# Create Amplify Deployment
resource "aws_amplify_deployment" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  environment = aws_amplify_environment.this.environment
}

# Create IAM Role for Amplify
resource "aws_iam_role" "amplify" {
  name        = "${var.project_name}-amplify-role"
  description = "Role for Amplify to manage resources"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
      },
    ]
  })
}

# Create IAM Policy for Amplify
resource "aws_iam_policy" "amplify" {
  name        = "${var.project_name}-amplify-policy"
  description = "Policy for Amplify to manage resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateEnvironment",
          "amplify:CreateDeployment",
        ]
        Resource = "*"
        Effect    = "Allow"
      },
    ]
  })
}

# Attach IAM Policy to Amplify Role
resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

# Output critical information
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.this.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.add_item.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
