# Use AWS provider version 5.1.0
terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

variable "app_name" {
  type        = string
  default     = "my-app"
  description = "The name of the application"
}

variable "github_repository" {
  type        = string
  default     = "my-username/my-repo"
  description = "The GitHub repository for the frontend application"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                     = "${var.stack_name}-user-pool"
  email_unique              = true
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                 = "${var.stack_name}-user-pool-client"
  user_pool_id         = aws_cognito_user_pool.this.id
  generate_secret      = false
  allowed_oauth_flows  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain          = "${var.app_name}.${var.stack_name}"
  user_pool_id    = aws_cognito_user_pool.this.id
}

# DynamoDB table
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  hash_key       = "cognito-username"
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  global_secondary_index {
    name               = "id-index"
    hash_key           = "id"
    range_key          = "cognito-username"
    read_capacity_units = 5
    write_capacity_units = 5
  }
  server_side_encryption {
    enabled = true
  }
}

# IAM roles and policies
# API Gateway to log to CloudWatch
resource "aws_iam_role" "api_gateway" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "API Gateway role to log to CloudWatch"

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

resource "aws_iam_policy" "api_gateway" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "API Gateway policy to log to CloudWatch"

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

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

# Amplify to manage resources
resource "aws_iam_role" "amplify" {
  name        = "${var.stack_name}-amplify-role"
  description = "Amplify role to manage resources"

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

resource "aws_iam_policy" "amplify" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Amplify policy to manage resources"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:CreateBranch",
          "amplify:DeleteBranch",
          "amplify:UpdateBranch",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

# Lambda to interact with DynamoDB and publish metrics to CloudWatch
resource "aws_iam_role" "lambda" {
  name        = "${var.stack_name}-lambda-role"
  description = "Lambda role to interact with DynamoDB and publish metrics to CloudWatch"

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

resource "aws_iam_policy" "lambda" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Lambda policy to interact with DynamoDB and publish metrics to CloudWatch"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
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

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# Lambda functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda/add-item.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda/get-item.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda/get-all-items.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda/update-item.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda/complete-item.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda/delete-item.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"
}

resource "aws_api_gateway_authorizer" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  name        = "${var.stack_name}-authorizer"
  type        = "COGNITO_USER_POOLS"
  provider_arns = [
    aws_cognito_user_pool.this.arn,
  ]
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.add_item.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.add_item.region}:${aws_lambda_function.add_item.account_id}:function:${aws_lambda_function.add_item.function_name}/invocations"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.get_item.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.get_item.region}:${aws_lambda_function.get_item.account_id}:function:${aws_lambda_function.get_item.function_name}/invocations"
}

resource "aws_api_gateway_method" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.get_all_items.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.get_all_items.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.get_all_items.region}:${aws_lambda_function.get_all_items.account_id}:function:${aws_lambda_function.get_all_items.function_name}/invocations"
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "PUT"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.update_item.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.update_item.region}:${aws_lambda_function.update_item.account_id}:function:${aws_lambda_function.update_item.function_name}/invocations"
}

resource "aws_api_gateway_method" "post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.post_item_done.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.complete_item.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.complete_item.region}:${aws_lambda_function.complete_item.account_id}:function:${aws_lambda_function.complete_item.function_name}/invocations"
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "DELETE"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.delete_item.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.delete_item.region}:${aws_lambda_function.delete_item.account_id}:function:${aws_lambda_function.delete_item.function_name}/invocations"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_integration.post_item,
    aws_api_gateway_integration.get_item,
    aws_api_gateway_integration.get_all_items,
    aws_api_gateway_integration.put_item,
    aws_api_gateway_integration.post_item_done,
    aws_api_gateway_integration.delete_item,
  ]

  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = var.app_name
  description = "Amplify App for ${var.app_name}"
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
}

resource "aws_amplify_environment" "prod" {
  app_id      = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.master.branch_name
  name        = "prod"
}

# Outputs
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

output "lambda_functions_arns" {
  value = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
