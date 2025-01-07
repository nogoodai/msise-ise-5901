terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

# Provider Configuration
provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region for deployment"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "Name of the stack"
  default     = "todo-app"
}

variable "domain_name" {
  description = "Custom domain name for Cognito"
  default     = "auth.todo-app.com"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  default     = "username/todo-app-frontend"
}

# Cognito User Pool for Authentication and User Management
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Cognito User Pool Client for OAuth2 Flows and Authentication Scopes
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name = "${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret = false

  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_route53_record" "cognito_domain" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cognito_user_pool_domain.user_pool_domain.cloudfront_distribution_arn
    zone_id                = aws_cognito_user_pool_domain.user_pool_domain.cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
}

# DynamoDB Table for Data Storage
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
    Environment = "production"
    Project     = "todo-app"
  }
}

# API Gateway for Serving API Requests and Integrating with Cognito for Authorization
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for Todo App"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.lambda_integration]
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for todo app API"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
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

# Lambda Functions for CRUD Operations on DynamoDB
resource "aws_lambda_function" "lambda_function_add_item" {
  function_name = "${var.stack_name}-add-item"
  filename      = "lambda_add_item.zip"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "lambda_function_get_item" {
  function_name = "${var.stack_name}-get-item"
  filename      = "lambda_get_item.zip"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "lambda_function_get_all_items" {
  function_name = "${var.stack_name}-get-all-items"
  filename      = "lambda_get_all_items.zip"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "lambda_function_update_item" {
  function_name = "${var.stack_name}-update-item"
  filename      = "lambda_update_item.zip"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "lambda_function_complete_item" {
  function_name = "${var.stack_name}-complete-item"
  filename      = "lambda_complete_item.zip"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-complete-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "lambda_function_delete_item" {
  function_name = "${var.stack_name}-delete-item"
  filename      = "lambda_delete_item.zip"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "lambda_integration_post" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_function_add_item.invoke_arn
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "lambda_integration_get" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_function_get_all_items.invoke_arn
}

resource "aws_api_gateway_resource" "item_id" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_resource.item.id
  path_part   = "{id}"
}

resource "aws_api_gateway_method" "get_item_id" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "lambda_integration_get_id" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_id.id
  http_method             = aws_api_gateway_method.get_item_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_function_get_item.invoke_arn
}

resource "aws_api_gateway_method" "put_item_id" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "lambda_integration_put" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_id.id
  http_method             = aws_api_gateway_method.put_item_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_function_update_item.invoke_arn
}

resource "aws_api_gateway_method" "post_item_id_done" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "lambda_integration_post_done" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_id.id
  http_method             = aws_api_gateway_method.post_item_id_done.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_function_complete_item.invoke_arn
}

resource "aws_api_gateway_method" "delete_item_id" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "lambda_integration_delete" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.item_id.id
  http_method             = aws_api_gateway_method.delete_item_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_function_delete_item.invoke_arn
}

# Amplify App for Frontend Hosting and Deployment from GitHub
resource "aws_amplify_app" "amplify_app" {
  name       = "${var.stack_name}-frontend"
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
    Name        = "${var.stack_name}-frontend"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"

  framework = "React"
  enable_auto_build = true

  environment_variables = {
    ENV = "prod"
  }

  tags = {
    Name        = "${var.stack_name}-master-branch"
    Environment = "production"
    Project     = "todo-app"
  }
}

# IAM Roles and Policies

# IAM Role for API Gateway to Log to CloudWatch
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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
    Name        = "${var.stack_name}-api-gateway-role"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.stack_name}-api-gateway-policy"
  role = aws_iam_role.api_gateway_role.id

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
      }
    ]
  })
}

# IAM Role for Amplify to Manage Resources
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
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
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

# IAM Role for Lambda to Interact with DynamoDB and Publish Metrics to CloudWatch
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
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.stack_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:*:*:*"
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

# CloudWatch Logs and Alarms

# CloudWatch Log Group for Lambda Functions
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.stack_name}-*"
  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-lambda-logs"
    Environment = "production"
    Project     = "todo-app"
  }
}

# CloudWatch Alarm for Lambda Errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.stack_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda function errors"
  alarm_actions       = [aws_sns_topic.lambda_error_alerts.arn]

  dimensions = {
    FunctionName = "${var.stack_name}-*"
  }

  tags = {
    Name        = "${var.stack_name}-lambda-error-alarm"
    Environment = "production"
    Project     = "todo-app"
  }
}

# CloudWatch Alarm for API Gateway 5XX Errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  alarm_name          = "${var.stack_name}-api-gateway-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = [aws_sns_topic.api_gateway_error_alerts.arn]

  dimensions = {
    ApiName = aws_api_gateway_rest_api.api_gateway.name
  }

  tags = {
    Name        = "${var.stack_name}-api-gateway-5xx-alarm"
    Environment = "production"
    Project     = "todo-app"
  }
}

# SNS Topic for Lambda Error Alerts
resource "aws_sns_topic" "lambda_error_alerts" {
  name = "${var.stack_name}-lambda-error-alerts"

  tags = {
    Name        = "${var.stack_name}-lambda-error-alerts"
    Environment = "production"
    Project     = "todo-app"
  }
}

# SNS Topic for API Gateway Error Alerts
resource "aws_sns_topic" "api_gateway_error_alerts" {
  name = "${var.stack_name}-api-gateway-error-alerts"

  tags = {
    Name        = "${var.stack_name}-api-gateway-error-alerts"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Data Sources

data "aws_route53_zone" "selected" {
  name         = "${var.domain_name}."
  private_zone = false
}

# Outputs

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_invoke_url" {
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.lambda_function_add_item.arn,
    aws_lambda_function.lambda_function_get_item.arn,
    aws_lambda_function.lambda_function_get_all_items.arn,
    aws_lambda_function.lambda_function_update_item.arn,
    aws_lambda_function.lambda_function_complete_item.arn,
    aws_lambda_function.lambda_function_delete_item.arn
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}
