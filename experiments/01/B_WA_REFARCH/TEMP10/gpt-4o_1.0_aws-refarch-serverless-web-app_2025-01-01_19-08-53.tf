terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "us-west-2"
}

variable "stack_name" {
  description = "The name of the stack for resource identification."
  default     = "my-stack"
}

variable "cognito_custom_domain" {
  description = "The custom domain for the Cognito User Pool."
  default     = "auth.example.com"
}

resource "aws_cognito_user_pool" "my_user_pool" {
  name = "user-pool-${var.stack_name}"

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name       = "cognito-user-pool-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

resource "aws_cognito_user_pool_client" "my_user_pool_client" {
  name                     = "user-pool-client-${var.stack_name}"
  user_pool_id             = aws_cognito_user_pool.my_user_pool.id
  generate_secret          = false
  explicit_auth_flows      = ["ALLOW_AUTH_CODE_FLOW", "ALLOW_IMPLICIT_FLOW"]
  allowed_oauth_flows      = ["code", "implicit"]
  allowed_oauth_scopes     = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name       = "cognito-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

resource "aws_cognito_user_pool_domain" "my_user_pool_domain" {
  domain      = var.cognito_custom_domain
  user_pool_id = aws_cognito_user_pool.my_user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "cognito-username"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  hash_key = "cognito-username"
  range_key = "id"

  server_side_encryption {
    enabled = true
  }
  
  tags = {
    Name       = "dynamodb-todo-table-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for managing to-do items"

  tags = {
    Name       = "api-gateway-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  deployment_id = aws_api_gateway_deployment.todo_dep.id

  description          = "Production stage"
  data_trace_enabled   = true
  logging_level        = "INFO"
  metrics_enabled      = true

  tags = {
    Name       = "api-gateway-stage-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

resource "aws_api_gateway_deployment" "todo_dep" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name           = "cognito-authorizer-${var.stack_name}"
  rest_api_id    = aws_api_gateway_rest_api.todo_api.id
  type           = "COGNITO_USER_POOLS"
  provider_arns  = [aws_cognito_user_pool.my_user_pool.arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name       = "lambda-exec-role-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

resource "aws_iam_policy" "lambda_exec_policy" {
  name        = "lambda-exec-policy-${var.stack_name}"
  description = "Policy to allow Lambda to interact with DynamoDB and CloudWatch"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_exec_policy.arn
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  filename      = "path/to/code/add-item.zip"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name       = "lambda-add-item-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

# Repeat above lambda definition with necessary modifications for other lambda functions: get_item, get_all_items, update_item, complete_item, delete_item

resource "aws_amplify_app" "frontend_app" {
  name = "todo-frontend-${var.stack_name}"
  repository = "https://github.com/user/repo"

  build_spec = <<-BUILD_SPEC
  version: 1.0
  frontend:
    phases:
      preBuild:
        commands:
          - npm install
      build:
        commands:
          - npm run build
    artifacts:
      baseDirectory: build
      files:
        - '**/*'
  BUILD_SPEC

  tags = {
    Name       = "amplify-app-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.frontend_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name       = "amplify-branch-master-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name       = "api-gateway-role-${var.stack_name}"
    Environment = "prod"
    Project    = "serverless-app"
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "api-gateway-policy-${var.stack_name}"
  description = "Policy to allow API Gateway to log to CloudWatch"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  policy_arn = aws_iam_policy.api_gateway_policy.arn
  role       = aws_iam_role.api_gateway_role.name
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.my_user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "The URL of the API Gateway."
  value       = aws_api_gateway_deployment.todo_dep.invoke_url
}

output "amplify_app_id" {
  description = "The ID of the Amplify App."
  value       = aws_amplify_app.frontend_app.id
}
