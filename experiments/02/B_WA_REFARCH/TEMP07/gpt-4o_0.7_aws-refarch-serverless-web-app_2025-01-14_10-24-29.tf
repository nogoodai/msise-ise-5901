terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name for tagging and naming resources"
  default     = "myapp"
}

variable "stack_name" {
  description = "Stack name for differentiating environments"
  default     = "prod"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.app_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain         = "${var.app_name}-${var.stack_name}"
  user_pool_id   = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.app_name}-${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id
  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]
  oauth {
    flows = ["authorization_code", "implicit"]
    scopes = ["email", "phone", "openid"]
  }
}

resource "aws_dynamodb_table" "todo" {
  name         = "todo-table-${var.stack_name}"
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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.app_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.app_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format          = "$context.identity.sourceIp - $context.identity.caller [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
  }
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  depends_on  = [aws_lambda_function.add_item]
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/api-gateway/${var.app_name}-${var.stack_name}"
  retention_in_days = 7
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.app_name}-${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
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

resource "aws_lambda_function" "add_item" {
  function_name = "${var.app_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  xray_tracing_mode = "Active"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo.name
    }
  }

  role = aws_iam_role.lambda_exec.arn

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = var.app_name
  }

  source_code_hash = filebase64sha256("lambda/add_item.zip")
  filename         = "lambda/add_item.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.app_name}-${var.stack_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-lambda-exec"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.app_name}-${var.stack_name}-dynamodb-policy"
  description = "Allows Lambda functions to access DynamoDB table for CRUD operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_amplify_app" "frontend" {
  name  = "${var.app_name}-${var.stack_name}-frontend"
  repository = "https://github.com/yourusername/yourrepo"

  build_spec = filebase64("amplify-build-spec.yml")

  environment_variables = {
    _LIVE_UPDATES = "[]"
  }

  auto_branch_creation_config {
    basic_auth_credentials = "yourusername:yourpassword"
    enable_auto_build = true
    enable_basic_auth = true
  }

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-frontend"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

resource "aws_amplify_branch" "main" {
  app_id     = aws_amplify_app.frontend.id
  branch_name = "master"

  tags = {
    Name        = "${var.app_name}-${var.stack_name}-frontend-master"
    Environment = var.stack_name
    Project     = var.app_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
