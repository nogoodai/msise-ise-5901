# Configure AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define variables
variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack"
}

variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "The GitHub token for Amplify"
}

# Networking
provider "aws" {
  region = var.aws_region
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.stack_name}-user-pool"
  username_attributes = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  supported_identity_providers = ["COGNITO"]
  allowed_oauth_flows          = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes        = ["email", "phone", "openid"]
  generate_secret              = false
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}.auth.${var.aws_region}.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "todo_table" {
  name           = "${var.stack_name}-todo-table"
  billing_mode   = "PROVISIONED"
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

  tags = {
    Name        = "${var.stack_name}-todo-table"
    Environment = "prod"
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-todo-api"
  description = "The API for the todo app"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "put_item_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "delete_item_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_method.get_item_method, aws_api_gateway_method.post_item_method, aws_api_gateway_method.put_item_method, aws_api_gateway_method.delete_item_method]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name = "${var.stack_name}-todo-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
  }

  quota {
    limit  = 5000
    offset = 0
    period = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "add_item_function" {
  filename      = "lambda-function.zip"
  function_name = "${var.stack_name}-add-item-function"
  handler       = "index.add_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "lambda-function.zip"
  function_name = "${var.stack_name}-get-item-function"
  handler       = "index.get_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "get_all_items_function" {
  filename      = "lambda-function.zip"
  function_name = "${var.stack_name}-get-all-items-function"
  handler       = "index.get_all_items"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "update_item_function" {
  filename      = "lambda-function.zip"
  function_name = "${var.stack_name}-update-item-function"
  handler       = "index.update_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "complete_item_function" {
  filename      = "lambda-function.zip"
  function_name = "${var.stack_name}-complete-item-function"
  handler       = "index.complete_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "delete_item_function" {
  filename      = "lambda-function.zip"
  function_name = "${var.stack_name}-delete-item-function"
  handler       = "index.delete_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

# API Gateway integration with Lambda functions
resource "aws_api_gateway_integration" "add_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.post_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_all_items_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_all_items_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "update_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.put_item_method.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "complete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.post_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.delete_item_method.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item_function.arn}/invocations"
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-todo-app"
  description = "The todo app"
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"
}

resource "aws_amplify_environment" "dev_environment" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "dev"
}

resource "aws_amplify_backend_environment" "dev_backend_environment" {
  app_id      = aws_amplify_app.todo_app.id
  environment = aws_amplify_environment.dev_environment.environment
}

resource "aws_amplify_service_role" "todo_service_role" {
  description = "The service role for the todo app"
}

# IAM roles and policies for API Gateway, Lambda, and Amplify
resource "aws_iam_role" "api_gateway_exec_role" {
  name        = "${var.stack_name}-api-gateway-exec-role"
  description = "The execution role for API Gateway"

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

resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
  name        = "${var.stack_name}-api-gateway-cloudwatch-policy"
  description = "The policy for API Gateway to write logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:${var.aws_region}:${aws_api_gateway_rest_api.todo_api.id}:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_exec_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.stack_name}-lambda-exec-role"
  description = "The execution role for Lambda"

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

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.stack_name}-lambda-dynamodb-policy"
  description = "The policy for Lambda to interact with DynamoDB"

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
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name        = "${var.stack_name}-lambda-cloudwatch-policy"
  description = "The policy for Lambda to publish metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}

resource "aws_iam_role" "amplify_exec_role" {
  name        = "${var.stack_name}-amplify-exec-role"
  description = "The execution role for Amplify"

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

resource "aws_iam_policy" "amplify_service_policy" {
  name        = "${var.stack_name}-amplify-service-policy"
  description = "The policy for Amplify to manage resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateEnvironment",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_service_attachment" {
  role       = aws_iam_role.amplify_exec_role.name
  policy_arn = aws_iam_policy.amplify_service_policy.arn
}

# Outputs
output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.add_item_function.arn,
    aws_lambda_function.get_item_function.arn,
    aws_lambda_function.get_all_items_function.arn,
    aws_lambda_function.update_item_function.arn,
    aws_lambda_function.complete_item_function.arn,
    aws_lambda_function.delete_item_function.arn,
  ]
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}
