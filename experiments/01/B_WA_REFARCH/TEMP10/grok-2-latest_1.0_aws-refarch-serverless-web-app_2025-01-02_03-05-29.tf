terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to deploy the solution"
}

variable "project_name" {
  type        = string
  default     = "todo-app"
  description = "Name of the project"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment of the deployment"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
  description = "Name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "your-username/your-repo"
  description = "GitHub repository for Amplify hosting"
}

provider "aws" {
  region = var.region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.environment}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers = false
    require_symbols = false
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.project_name}-${var.environment}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret     = false

  tags = {
    Name        = "${var.project_name}-${var.environment}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-user-pool-domain"
    Environment = var.environment
    Project     = var.project_name
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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.project_name}-${var.environment}-api"
  description = "API Gateway for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.project_name}-${var.environment}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api_gateway.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_authorizer.cognito_authorizer,
  ]
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log_group.arn
    format          = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-stage-prod"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name         = "${var.project_name}-${var.environment}-usage-plan"
  description  = "Usage plan for ${var.project_name} API"
  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_stage.prod_stage.stage_name
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
    Name        = "${var.project_name}-${var.environment}-usage-plan"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_method_settings" "all_methods" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = aws_api_gateway_stage.prod_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/api-gateway/${var.project_name}-${var.environment}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-${var.environment}-api-gateway-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-${var.environment}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-add-item"
    Environment = var.environment
    Project     = var.project_name
  }

  # Dummy code, replace with actual source
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

resource "aws_lambda_function" "get_item" {
  # Similar configuration as 'add_item' but for GET /item/{id}
}

resource "aws_lambda_function" "get_all_items" {
  # Similar configuration as 'add_item' but for GET /item
}

resource "aws_lambda_function" "update_item" {
  # Similar configuration as 'add_item' but for PUT /item/{id}
}

resource "aws_lambda_function" "complete_item" {
  # Similar configuration as 'add_item' but for POST /item/{id}/done
}

resource "aws_lambda_function" "delete_item" {
  # Similar configuration as 'add_item' but for DELETE /item/{id}
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name       = "${var.project_name}-${var.environment}"
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
    ENV = var.environment
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-amplify-app"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-amplify-branch-master"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.environment}-api-gateway-role"

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
    Name        = "${var.project_name}-${var.environment}-api-gateway-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.project_name}-${var.environment}-api-gateway-policy"
  description = "Policy for API Gateway to log to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/api-gateway/${var.project_name}-${var.environment}:*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-api-gateway-policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-${var.environment}-amplify-role"

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
    Name        = "${var.project_name}-${var.environment}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.project_name}-${var.environment}-amplify-policy"
  description = "Policy for Amplify to manage resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "s3:*",
          "cloudfront:*",
          "route53:*",
          "acm:*",
          "logs:*"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-amplify-policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.environment}-lambda-role"

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
    Name        = "${var.project_name}-${var.environment}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-${var.environment}-lambda-policy"
  description = "Policy for Lambda to interact with DynamoDB and CloudWatch"

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
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.project_name}-${var.environment}-*:*"
      },
      {
        Action   = [
          "cloudwatch:PutMetricData"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
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
    Name        = "${var.project_name}-${var.environment}-lambda-error-alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "Cognito User Pool ID"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.user_pool_client.id
  description = "Cognito User Pool Client ID"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.user_pool_domain.domain
  description = "Cognito Domain"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "DynamoDB Table Name"
}

output "api_gateway_url" {
  value       = aws_api_gateway_stage.prod_stage.invoke_url
  description = "API Gateway URL"
}

output "amplify_app_id" {
  value       = aws_amplify_app.amplify_app.id
  description = "Amplify App ID"
}

output "amplify_default_domain" {
  value       = aws_amplify_app.amplify_app.default_domain
  description = "Amplify Default Domain"
}
