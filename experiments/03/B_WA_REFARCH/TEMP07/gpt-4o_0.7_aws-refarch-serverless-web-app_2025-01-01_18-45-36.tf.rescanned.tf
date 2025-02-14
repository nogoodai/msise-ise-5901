terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  type        = string
  description = "The name for the stack of resources."
  default     = "my-stack"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository URL for Amplify App"
}

variable "cognito_domain_prefix" {
  type        = string
  description = "Custom domain prefix for Cognito"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows = ["code", "implicit"]

  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret      = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-gateway-${var.stack_name}"
  description = "API for managing to-do items"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  body = file("${path.module}/api_swagger.json")

  minimum_compression_size = 0

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = "$context.requestId $context.identity.sourceIp $context.identity.caller $context.identity.user $context.requestTime $context.status $context.protocol $context.responseLength $context.path $context.domainName $context.accountId"
  }

  xray_tracing_enabled = true

  tags = {
    Name        = "api-gateway-prod-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
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

  tags = {
    Name        = "usage-plan-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "crud_function" {
  for_each = {
    "add_item"     : "POST /item",
    "get_item"     : "GET /item/{id}",
    "get_all_items": "GET /item",
    "update_item"  : "PUT /item/{id}",
    "complete_item": "POST /item/{id}/done",
    "delete_item"  : "DELETE /item/{id}"
  }

  function_name = "${each.key}-${var.stack_name}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = "${path.module}/lambda/${each.key}.zip"

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${each.key}-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-app-${var.stack_name}"

  repository = var.github_repo
  build_spec = file("${path.module}/buildspec.yml")

  environment_variables = {
    _LIVE_UPDATES = "ENABLED"
  }

  auto_branch_creation_config {
    patterns = ["main", "master"]
  }

  oauth_token = var.github_oauth_token

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
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
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda-dynamodb-policy-${var.stack_name}"
  description = "Policy for Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "lambda-dynamodb-policy-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
  role       = aws_iam_role.lambda_exec_role.name
}

resource "aws_iam_role" "api_gateway_exec_role" {
  name = "api-gateway-exec-role-${var.stack_name}"

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
    Name        = "api-gateway-exec-role-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "api_gateway_logging_policy" {
  name        = "api-gateway-logging-policy-${var.stack_name}"
  description = "Policy for API Gateway to log to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "api-gateway-logging-policy-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_logging_attach" {
  policy_arn = aws_iam_policy.api_gateway_logging_policy.arn
  role       = aws_iam_role.api_gateway_exec_role.name
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.api.name}"

  tags = {
    Name        = "api-gateway-logs-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

variable "github_oauth_token" {
  type        = string
  description = "GitHub OAuth token for accessing private repositories."
  sensitive   = true
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito User Pool"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_url" {
  value       = aws_api_gateway_stage.prod.invoke_url
  description = "The URL of the API Gateway stage"
}

output "amplify_app_id" {
  value       = aws_amplify_app.amplify_app.id
  description = "The ID of the Amplify app"
}

output "lambda_function_arns" {
  value       = { for k, f in aws_lambda_function.crud_function : k => f.arn }
  description = "The ARNs of the Lambda functions"
}
