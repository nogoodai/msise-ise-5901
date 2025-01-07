terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Stack name for resource naming"
  default     = "todo-app"
}

variable "application_name" {
  description = "Application name for resource naming"
  default     = "my-todo-app"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito custom domain"
  default     = "auth"
}

variable "amplify_github_repo" {
  description = "GitHub repo URL for Amplify"
  default     = "https://github.com/user/my-todo-app-frontend"
}

# Provider
provider "aws" {
  region = var.region
}

# Networking
# Not explicitly required in the architecture but useful for a complete setup
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "${var.stack_name}-vpc"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.stack_name}-public-subnet"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Authentication with Amazon Cognito
resource "aws_cognito_user_pool" "pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${aws_amplify_app.frontend_app.default_domain}"]
  logout_urls                          = ["https://${aws_amplify_app.frontend_app.default_domain}"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.pool.id

  tags = {
    Name        = "${var.stack_name}-user-pool-domain"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Database with DynamoDB
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
    Name        = "${var.stack_name}-todo-table"
    Environment = "prod"
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-todo-api"
  description = "API for todo application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-todo-api"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.pool.arn]
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.todo_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "todo_api_stage" {
  deployment_id = aws_api_gateway_deployment.todo_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name = "${var.stack_name}-todo-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_stage.todo_api_stage.stage_name
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
    Name        = "${var.stack_name}-todo-usage-plan"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_method_settings" "todo_api_settings" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = aws_api_gateway_stage.todo_api_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename         = "lambda_functions/add_item.zip"
  function_name    = "${var.stack_name}-add-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/add_item.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename         = "lambda_functions/get_item.zip"
  function_name    = "${var.stack_name}-get-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/get_item.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename         = "lambda_functions/get_all_items.zip"
  function_name    = "${var.stack_name}-get-all-items"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/get_all_items.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename         = "lambda_functions/update_item.zip"
  function_name    = "${var.stack_name}-update-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/update_item.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename         = "lambda_functions/complete_item.zip"
  function_name    = "${var.stack_name}-complete-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/complete_item.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-complete-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename         = "lambda_functions/delete_item.zip"
  function_name    = "${var.stack_name}-delete-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/delete_item.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Amplify for Frontend Hosting
resource "aws_amplify_app" "frontend_app" {
  name       = "${var.stack_name}-frontend-app"
  repository = var.amplify_github_repo

  build_spec = <<-EOT
    version: 0.1
    frontend:
      phases:
        preBuild:
          commands:
            - yarn install
        build:
          commands:
            - yarn build
      artifacts:
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  custom_rules = [
    {
      source = "</^((?!.(css|gif|ico|jpg|js|png|txt|svg|woff|ttf)$).)*$/>",
      status = "200",
      target = "/index.html"
    }
  ]

  tags = {
    Name        = "${var.stack_name}-frontend-app"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.frontend_app.id
  branch_name = "master"
  framework   = "React"
  stage       = "PRODUCTION"
}

# IAM Roles and Policies
resource "aws_iam_role" "apigateway_role" {
  name = "${var.stack_name}-apigateway-role"

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
    Name        = "${var.stack_name}-apigateway-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "apigateway_logging_policy" {
  name = "${var.stack_name}-apigateway-logging-policy"
  role = aws_iam_role.apigateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

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
    Name        = "${var.stack_name}-amplify-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "amplify_management_policy" {
  name = "${var.stack_name}-amplify-management-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "amplify:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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
    Name        = "${var.stack_name}-lambda-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_cloudwatch_policy" {
  name = "${var.stack_name}-lambda-cloudwatch-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.todo_api.name}"

  tags = {
    Name        = "${var.stack_name}-api-gateway-logs"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.stack_name}-lambda-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    FunctionName = aws_lambda_function.add_item.function_name
  }

  tags = {
    Name        = "${var.stack_name}-lambda-error-alarm"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_alarm" {
  alarm_name          = "${var.stack_name}-api-gateway-4xx-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors API Gateway 4xx errors"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    ApiName = aws_api_gateway_rest_api.todo_api.name
  }

  tags = {
    Name        = "${var.stack_name}-api-gateway-4xx-alarm"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "cognito_domain_url" {
  value = aws_cognito_user_pool_domain.domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.todo_api_stage.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.frontend_app.default_domain
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn
  ]
}
