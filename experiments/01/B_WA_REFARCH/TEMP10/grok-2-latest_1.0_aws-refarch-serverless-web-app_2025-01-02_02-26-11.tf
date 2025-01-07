terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Provider configuration for AWS
provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Name of the stack"
  type        = string
  default     = "todo-app"
}

variable "application_name" {
  description = "Name of the application"
  type        = string
  default     = "todo-web-app"
}

variable "github_repo_url" {
  description = "GitHub repository URL for Amplify"
  type        = string
  default     = "https://github.com/user/todo-frontend"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "todo_user_pool" {
  name = "${var.application_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
  }

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "todo_user_pool_client" {
  name         = "${var.application_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.todo_user_pool.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  allowed_oauth_flows = [
    "code",
    "implicit"
  ]

  allowed_oauth_scopes = [
    "email",
    "phone",
    "openid"
  ]

  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "${var.application_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_user_pool.id
}

# DynamoDB table for data storage with partition and sort keys
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
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-api"
  description = "API for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "todo_api_authorizer" {
  name          = "${var.application_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_user_pool.arn]
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.todo_api.body))
  }
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name         = "${var.application_name}-usage-plan"
  description  = "Usage plan for ${var.application_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_api_deployment.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "lambda_functions" {
  for_each = toset([
    "add-item",
    "get-item",
    "get-all-items",
    "update-item",
    "complete-item",
    "delete-item"
  ])

  function_name = "${var.application_name}-${each.key}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.application_name}-${each.key}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "todo_amplify_app" {
  name       = "${var.application_name}-amplify"
  repository = var.github_repo_url

  build_spec = <<-EOT
    version: 0.1
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
      cache:
        paths:
          - node_modules/**/*
  EOT

  tags = {
    Name        = "${var.application_name}-amplify"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "todo_master_branch" {
  app_id      = aws_amplify_app.todo_amplify_app.id
  branch_name = "master"

  framework = "React"
  stage     = "PRODUCTION"

  environment_variables = {
    API_URL = aws_api_gateway_deployment.todo_api_deployment.invoke_url
  }

  tags = {
    Name        = "${var.application_name}-amplify-master"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM roles and policies
# API Gateway to log to CloudWatch
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

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
    Name        = "${var.application_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.application_name}-api-gateway-policy"
  path        = "/"
  description = "Policy for API Gateway to write to CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "logs:CreateLogGroup"
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/api-gateway/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

# Amplify to manage resources
resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-amplify-role"

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
    Name        = "${var.application_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.application_name}-amplify-policy"
  path        = "/"
  description = "Policy for Amplify to manage resources"

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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Lambda to interact with DynamoDB and publish metrics to CloudWatch
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-lambda-role"

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
    Name        = "${var.application_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.application_name}-lambda-policy"
  path        = "/"
  description = "Policy for Lambda to interact with DynamoDB and CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
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

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Data sources
data "aws_caller_identity" "current" {}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.todo_api.name}"

  tags = {
    Name        = "${aws_api_gateway_rest_api.todo_api.name}-logs"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_errors" {
  alarm_name          = "${var.application_name}-api-gateway-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors 4XX errors on API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.todo_api.name
  }

  tags = {
    Name        = "${var.application_name}-api-gateway-4xx-errors"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = aws_lambda_function.lambda_functions

  name              = "/aws/lambda/${each.value.function_name}"
  retention_in_days = 30

  tags = {
    Name        = "${each.value.function_name}-logs"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = aws_lambda_function.lambda_functions

  alarm_name          = "${each.value.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda errors for ${each.value.function_name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${each.value.function_name}-errors"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_user_pool_client.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.todo_user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_api_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_amplify_app.id
}

output "amplify_branch_id" {
  value = aws_amplify_branch.todo_master_branch.id
}
