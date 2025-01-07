terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

# Networking and DNS
resource "aws_route53_zone" "main" {
  name = var.domain_name
  tags = {
    Name        = "main-route53-zone"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-user-pool-${var.environment}"
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.project_name}-user-pool-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route53_record" "cognito_domain" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "auth.${aws_route53_zone.main.name}"
  type    = "A"

  alias {
    name                   = aws_cognito_user_pool_domain.cognito_domain.cloudfront_distribution_dns_name
    zone_id                = aws_cognito_user_pool_domain.cognito_domain.cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain       = "${var.project_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB
resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.environment}"
  billing_mode = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  hash_key  = "cognito-username"
  range_key = "id"

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
    Name        = "todo-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-api-${var.environment}"
  description = "API Gateway for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.project_name}-cognito-authorizer-${var.environment}"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_method.api_method]
}

resource "aws_api_gateway_usage_plan" "api_usage_plan" {
  name         = "${var.project_name}-api-usage-plan-${var.environment}"
  description  = "Usage plan for ${var.project_name} API"
  product_code = "prod-${var.project_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
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

  tags = {
    Name        = "${var.project_name}-api-usage-plan"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "lambda_function" {
  for_each = var.lambda_functions

  function_name = each.value.name
  role          = aws_iam_role.lambda_role.arn
  handler       = each.value.handler
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = each.value.filename
  source_code_hash = filebase64sha256(each.value.filename)

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = each.value.name
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  for_each      = var.lambda_functions
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# Amplify
resource "aws_amplify_app" "amplify_app" {
  name       = "${var.project_name}-frontend-${var.environment}"
  repository = var.github_repo_url
  access_token = var.github_personal_access_token

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

  tags = {
    Name        = "${var.project_name}-frontend"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "main_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.project_name}-frontend-branch"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-api-gateway-role-${var.environment}"

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
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.project_name}-api-gateway-policy-${var.environment}"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-amplify-role-${var.environment}"

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
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.project_name}-amplify-policy-${var.environment}"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*",
          "cloudformation:*",
          "route53:*",
          "iam:*"
        ],
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

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
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${var.environment}"
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
        ],
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.api.name}"

  tags = {
    Name        = "api-gateway-log-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  for_each = var.lambda_functions

  name = "/aws/lambda/${aws_lambda_function.lambda_function[each.key].function_name}"

  tags = {
    Name        = "${each.value.name}-log-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  for_each = var.lambda_functions

  alarm_name          = "${aws_lambda_function.lambda_function[each.key].function_name}-ErrorAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors lambda errors for ${aws_lambda_function.lambda_function[each.key].function_name}"
  alarm_actions      = [var.sns_topic_arn]

  dimensions = {
    FunctionName = aws_lambda_function.lambda_function[each.key].function_name
  }

  tags = {
    Name        = "${aws_lambda_function.lambda_function[each.key].function_name}-error-alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_errors" {
  alarm_name          = "${aws_api_gateway_rest_api.api.name}-5xxErrorsAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors 5XX errors for ${aws_api_gateway_rest_api.api.name}"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ApiName = aws_api_gateway_rest_api.api.name
  }

  tags = {
    Name        = "${aws_api_gateway_rest_api.api.name}-5xx-errors-alarm"
    Environment = var.environment
    Project     = var.project_name
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
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "lambda_function_arns" {
  value = { for k, v in aws_lambda_function.lambda_function : k => v.arn }
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}

# Variables
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for naming resources"
  type        = string
  default     = "todo-app"
}

variable "domain_name" {
  description = "Root domain name"
  type        = string
}

variable "cognito_callback_urls" {
  description = "List of callback URLs for Cognito"
  type        = list(string)
  default     = []
}

variable "cognito_logout_urls" {
  description = "List of logout URLs for Cognito"
  type        = list(string)
  default     = []
}

variable "github_repo_url" {
  description = "GitHub repository URL for Amplify"
  type        = string
}

variable "github_personal_access_token" {
  description = "GitHub Personal Access Token for Amplify"
  type        = string
}

variable "lambda_functions" {
  description = "Map of Lambda functions to create"
  type = map(object({
    name     = string
    handler  = string
    filename = string
  }))
  default = {
    addItem = {
      name     = "add-item"
      handler  = "addItem.handler"
      filename = "addItem.zip"
    },
    getItem = {
      name     = "get-item"
      handler  = "getItem.handler"
      filename = "getItem.zip"
    },
    getAllItems = {
      name     = "get-all-items"
      handler  = "getAllItems.handler"
      filename = "getAllItems.zip"
    },
    updateItem = {
      name     = "update-item"
      handler  = "updateItem.handler"
      filename = "updateItem.zip"
    },
    completeItem = {
      name     = "complete-item"
      handler  = "completeItem.handler"
      filename = "completeItem.zip"
    },
    deleteItem = {
      name     = "delete-item"
      handler  = "deleteItem.handler"
      filename = "deleteItem.zip"
    }
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  type        = string
}
