terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "aws_region" {
  description = "AWS region to launch resources"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Stack name for tagging and naming resources"
  default     = "todo-app"
}

variable "cognito_domain" {
  description = "Custom domain name for Cognito"
  default     = "auth.todo-app.com"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  default     = "username/todo-app-frontend"
}

variable "github_oauth_token" {
  description = "GitHub OAuth token for Amplify"
  default     = ""
}

# Provider
provider "aws" {
  region = var.aws_region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "todo-user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "todo-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "todo-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "phone"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "todo-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain       = var.cognito_domain
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
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
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for TODO Application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "todo-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "CognitoAuthorizer"
  rest_api_id            = aws_api_gateway_rest_api.todo_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.todo_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.header.Content-Type" = true
  }
}

resource "aws_api_gateway_integration" "add_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.todo_resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.add_item.invoke_arn
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [
    aws_api_gateway_integration.add_item_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  variables = {
    deployed_at = timestamp()
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "todo-usage-plan-${var.stack_name}"
  description = "Usage plan for TODO API"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "todo-usage-plan-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_account" "todo_api_account" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch_role.arn
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "todo-add-item-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_dynamodb_role.arn

  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "todo-add-item-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_permission" "add_item_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

# Amplify
resource "aws_amplify_app" "todo_frontend" {
  name       = "todo-frontend-${var.stack_name}"
  repository = var.github_repo

  build_spec = <<-EOT
    version: 0.1
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  environment_variables = {
    ENV = "prod"
  }

  tags = {
    Name        = "todo-frontend-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_frontend.id
  branch_name = "master"

  framework = "React"
  enable_auto_build = true

  tags = {
    Name        = "todo-frontend-master-branch-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "apigateway_cloudwatch_role" {
  name = "todo-apigateway-cloudwatch-role-${var.stack_name}"

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
    Name        = "todo-apigateway-cloudwatch-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "apigateway_cloudwatch_policy" {
  name = "todo-apigateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.apigateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "todo-amplify-role-${var.stack_name}"

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
    Name        = "todo-amplify-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "todo-amplify-policy-${var.stack_name}"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
          "s3:*",
          "cloudformation:*",
          "iam:PassRole"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "lambda_dynamodb_role" {
  name = "todo-lambda-dynamodb-role-${var.stack_name}"

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
    Name        = "todo-lambda-dynamodb-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "todo-lambda-dynamodb-policy-${var.stack_name}"
  role = aws_iam_role.lambda_dynamodb_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.add_item.function_name}"
  retention_in_days = 30

  tags = {
    Name        = "todo-lambda-logs-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name                = "todo-lambda-error-alarm-${var.stack_name}"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "1"
  metric_name               = "Errors"
  namespace                 = "AWS/Lambda"
  period                    = "60"
  statistic                 = "Sum"
  threshold                 = "0"
  alarm_description         = "This metric monitors lambda errors"
  insufficient_data_actions = []

  dimensions = {
    FunctionName = aws_lambda_function.add_item.function_name
  }

  alarm_actions = [
    "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:default-alarm-topic"
  ]

  tags = {
    Name        = "todo-lambda-error-alarm-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.cognito_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_frontend.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.master.branch_name
}

data "aws_caller_identity" "current" {}
