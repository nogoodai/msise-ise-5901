terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "us-west-2"
}

variable "project_name" {
  type        = string
  default     = "serverless-web-app"
  description = "Project name for resource naming"
}

variable "stack_name" {
  type        = string
  default     = "prod"
  description = "Stack name for environment and resource naming"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/repo"
  description = "GitHub repository URL for Amplify"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "GitHub branch for Amplify"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub token for Amplify"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.project_name}-${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.project_name}-${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls       = ["https://example.com/callback"]
  logout_urls         = ["https://example.com/logout"]
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-cognito-domain"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name                = "todo-table-${var.stack_name}"
  read_capacity_units = 5
  write_capacity_units = 5
  hash_key             = "cognito-username"
  range_key            = "id"
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
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.project_name}-${var.stack_name}-api"
  description = "${var.project_name} API"
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.project_name
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
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_resource" "item_id" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.this.id
  path_part   = "{id}"
}

resource "aws_api_gateway_method" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "lambda_post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "lambda_get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_all_items.arn}/invocations"
}

resource "aws_api_gateway_integration" "lambda_get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "lambda_put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "lambda_delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "lambda_post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.post_item_done.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "this" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

resource "aws_api_gateway_deployment" "this" {
  depends_on  = [aws_api_gateway_integration.lambda_post, aws_api_gateway_integration.lambda_get, aws_api_gateway_integration.lambda_get_item, aws_api_gateway_integration.lambda_put, aws_api_gateway_integration.lambda_delete, aws_api_gateway_integration.lambda_post_item_done]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = var.stack_name
}

# Lambda Function
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda-exec.arn
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda-exec.arn
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-get-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda-exec.arn
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-get-all-items"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda-exec.arn
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-update-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda-exec.arn
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-delete-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project_name}-${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda-exec.arn
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-complete-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda-exec" {
  name        = "${var.project_name}-${var.stack_name}-lambda-exec"
  description = "Execution role for Lambda functions"

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
      }
    ]
  })
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-lambda-exec"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda-exec" {
  name        = "${var.project_name}-${var.stack_name}-lambda-exec"
  description = "Policy for Lambda execution"

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
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.this.arn
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-lambda-exec"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda-exec" {
  role       = aws_iam_role.lambda-exec.name
  policy_arn = aws_iam_policy.lambda-exec.arn
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.project_name}-${var.stack_name}"
  description = "${var.project_name} Amplify App"
  tags = {
    Name        = "${var.project_name}-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_app_version" "this" {
  app_id      = aws_amplify_app.this.id
  source_url  = var.github_repo
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "api_gateway_deployment_id" {
  value = aws_api_gateway_deployment.this.id
}

output "lambda_add_item_arn" {
  value = aws_lambda_function.add_item.arn
}

output "lambda_get_item_arn" {
  value = aws_lambda_function.get_item.arn
}

output "lambda_get_all_items_arn" {
  value = aws_lambda_function.get_all_items.arn
}

output "lambda_update_item_arn" {
  value = aws_lambda_function.update_item.arn
}

output "lambda_delete_item_arn" {
  value = aws_lambda_function.delete_item.arn
}

output "lambda_complete_item_arn" {
  value = aws_lambda_function.complete_item.arn
}
