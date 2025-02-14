```hcl
terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "todo-app"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito custom domain"
  type        = string
  default     = "auth"
}

variable "github_repo" {
  description = "GitHub repository for Amplify app"
  type        = string
  default     = "your-org/your-repo"
}

variable "amplify_branch_name" {
  description = "Branch name for Amplify app"
  type        = string
  default     = "master"
}

provider "aws" {
  region = var.region
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project}-${var.environment}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  mfa_configuration = "OPTIONAL"

  tags = {
    Name        = "${var.project}-${var.environment}-user-pool"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.project}-${var.environment}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.project}-${var.environment}-user-pool-client"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.cognito_domain_prefix}-${var.project}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.environment}"
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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.environment}"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project}-${var.environment}-api"
  description = "API Gateway for ${var.project} ${var.environment}"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Name        = "${var.project}-${var.environment}-api"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_stage.prod]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log_group.arn
    format          = "$context.identity.sourceIp $context.identity.caller $context.identity.user [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
  }
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_deployment.deployment.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.project}-${var.environment}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.project}-${var.environment}-usage-plan"
  description = "Usage plan for ${var.project} ${var.environment}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
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
    Name        = "${var.project}-${var.environment}-usage-plan"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_lambda_function" "lambda_functions" {
  for_each = toset(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"])

  function_name = "${var.project}-${var.environment}-${each.key}"
  handler       = "${each.key}.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  filename         = "lambda-${each.key}.zip"
  source_code_hash = filebase64sha256("lambda-${each.key}.zip")

  role = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project}-${var.environment}-${each.key}"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-${var.environment}-lambda-role"

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
    Name        = "${var.project}-${var.environment}-lambda-role"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project}-${var.environment}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/*:*"
      },
      {
        Action   = "xray:PutTraceSegments"
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = "cloudwatch:PutMetricData"
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "app" {
  name       = "${var.project}-${var.environment}-app"
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
    EOT

  tags = {
    Name        = "${var.project}-${var.environment}-app"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = var.amplify_branch_name

  tags = {
    Name        = "${var.project}-${var.environment}-branch"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project}-${var.environment}-api-gateway-role"

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
    Name        = "${var.project}-${var.environment}-api-gateway-role"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.project}-${var.environment}-api-gateway-policy"
  role = aws_iam_role.api_gateway_role.id

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
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/apigateway/*:*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project}-${var.environment}-amplify-role"

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
    Name        = "${var.project}-${var.environment}-amplify-role"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.project}-${var.environment}-amplify-policy"
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

resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/apigateway/${aws_api_gateway_rest_api.api.name}"
  retention_in_days = 30
  kms_key_id        = data.aws_kms_key.cloudwatch.arn

  tags = {
    Name        = "${aws_api_gateway_rest_api.api.name}-log-group"
    Project     = var.project
    Environment = var.environment
  }
}

data "aws_kms_key" "cloudwatch" {
  key_id = "alias/aws/logs"
}

resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_errors" {
  alarm_name          = "${var.project}-${var.environment}-api-gateway-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "60"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors 4XX errors from API Gateway"
  alarm_actions       = []

  dimensions = {
    ApiName = aws_api_gateway_rest_api.api.name
  }

  tags = {
    Name        = "${var.project}-${var.environment}-api-gateway-4xx-errors"
    Project     = var.project
    Environment = var.environment
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
  alarm_description   = "This metric monitors errors from Lambda function ${each.value.function_name}"
  alarm_actions       = []

  dimensions = {
    FunctionName = each.value.function_name
  }

  tags = {
    Name        = "${each.value.function_name}-errors"
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_accessanalyzer_analyzer" "access_analyzer" {
  analyzer_name = "${var.project}-${var.environment}-access-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name        = "${var.project}-${var.environment}-access-analyzer"
    Project     = var.project
    Environment = var.environment
  }
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito User Pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.user_pool_client.id
  description = "The ID of the Cognito User Pool Client"
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "The domain of the Cognito User Pool"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_url" {
  value       = aws_api_gateway_deployment.deployment.invoke_url
  description = "The URL of the API Gateway"
}

output "amplify_app_id" {
  value       = aws_amplify_app.app.id
  description = "The ID of the Amplify App"
}

output "amplify_app_url" {
  value       = aws_amplify_app.app.default_domain
  description = "The URL of the Amplify App"
}
```