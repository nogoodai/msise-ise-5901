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

variable "project_name" {
  description = "The name of the project"
  default     = "todo-app"
}

variable "stack_name" {
  description = "The name of the stack"
  default     = "prod"
}

variable "cognito_domain" {
  description = "Custom domain name for Cognito"
  default     = "auth.example.com"
}

variable "github_repo_owner" {
  description = "GitHub repository owner"
  default     = "your-github-username"
}

variable "github_repo_name" {
  description = "GitHub repository name"
  default     = "your-todo-app-repo"
}

variable "github_branch" {
  description = "GitHub branch to deploy from"
  default     = "master"
}

# Provider Configuration
provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app_user_pool" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app_user_pool_client" {
  name         = "${var.project_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.todo_app_user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${var.cognito_domain}/callback"]
  logout_urls                          = ["https://${var.cognito_domain}/logout"]
  allowed_oauth_flows_user_pool_client = true

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_app_user_pool_domain" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_app_user_pool.id
}

resource "aws_route53_record" "cognito_custom_domain" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.cognito_domain
  type    = "A"

  alias {
    name                   = aws_cognito_user_pool_domain.todo_app_user_pool_domain.cloudfront_distribution_arn
    zone_id                = aws_cognito_user_pool_domain.todo_app_user_pool_domain.cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
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
    Name        = "${var.project_name}-todo-table"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.project_name}-${var.stack_name}-api"
  description = "API for ${var.project_name} application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.project_name}-api-deployment"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_usage_plan" "todo_api_usage_plan" {
  name         = "${var.project_name}-${var.stack_name}-usage-plan"
  description  = "Usage plan for ${var.project_name} API"
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

  tags = {
    Name        = "${var.project_name}-api-usage-plan"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.project_name}-${var.stack_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.todo_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.todo_app_user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  filename      = "add_item.zip" # Placeholder for function code
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-add-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# (Similar resources for other CRUD operations: get_item, get_all_items, update_item, complete_item, delete_item)

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "add_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.add_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.add_item.invoke_arn
}

# (Similar resources for other CRUD operations)

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-role"

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
    Name        = "${var.project_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "api_gateway_logging_policy" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-logging-policy"

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

resource "aws_iam_role_policy_attachment" "api_gateway_logging_policy_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_logging_policy.arn
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.stack_name}-lambda-role"

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
    Name        = "${var.project_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "${var.project_name}-${var.stack_name}-lambda-dynamodb-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name = "${var.project_name}-${var.stack_name}-lambda-cloudwatch-policy"

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

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-${var.stack_name}-amplify-role"

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
    Name        = "${var.project_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name = "${var.project_name}-${var.stack_name}-amplify-policy"

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

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Amplify
resource "aws_amplify_app" "todo_app" {
  name       = "${var.project_name}-${var.stack_name}"
  repository = "https://github.com/${var.github_repo_owner}/${var.github_repo_name}"

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
    ENV = var.stack_name
  }

  tags = {
    Name        = "${var.project_name}-app"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch

  tags = {
    Name        = "${var.project_name}-master-branch"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Monitoring and Alarms
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.todo_api.name}"

  tags = {
    Name        = "${var.project_name}-api-gateway-logs"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-${var.stack_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.add_item.function_name
  }

  tags = {
    Name        = "${var.project_name}-lambda-errors-alarm"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app_user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app_user_pool_client.id
}

output "cognito_domain_url" {
  value = "https://${aws_cognito_user_pool_domain.todo_app_user_pool_domain.domain}.auth.${var.region}.amazoncognito.com"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_api_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_app_default_domain" {
  value = aws_amplify_app.todo_app.default_domain
}

# Data Sources
data "aws_route53_zone" "selected" {
  name         = "example.com."
  private_zone = false
}
