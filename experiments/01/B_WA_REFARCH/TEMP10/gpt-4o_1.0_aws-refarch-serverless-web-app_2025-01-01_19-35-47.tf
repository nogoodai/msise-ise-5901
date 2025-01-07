terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "stack_name" {
  description = "Application stack name"
  type        = string
  default     = "myapp"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id         = aws_cognito_user_pool.user_pool.id
  name                 = "${var.stack_name}-user-pool-client"
  generate_secret      = false
  allowed_oauth_flows  = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "${var.stack_name}-${var.environment}-auth"
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Project     = var.stack_name
    Environment = var.environment
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = var.environment
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  tags = {
    Name        = "${var.stack_name}-api-stage"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode(resource))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
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
    Name        = "${var.stack_name}-usage-plan"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "lambda_function" {
  count       = 6
  function_name = element(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"], count.index)
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_exec.arn

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.user_pool.id
      DYNAMODB_TABLE_NAME  = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name = "${var.stack_name}-lambda-${element(["add", "get", "get-all", "update", "complete", "delete"], count.index)}-item"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_amplify_app" "amplify_app" {
  name  = "${var.stack_name}"
  repository = "https://github.com/username/repository"

  build_spec = filebase64("amplify-build-spec.yml")

  environment_variables = {
    _LIVE_UPDATES = "true"
  }

  default_domain_prefix = var.stack_name

  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id     = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.stack_name}-amplify-master-branch"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "${var.stack_name}-lambda-exec-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_full_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy" "api_gateway_logs" {
  name = "${var.stack_name}-api-gateway-logs"

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
        Resource = "*"
      }
    ]
  })

  role = aws_iam_role.api_gateway_role.id
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name = "${var.stack_name}-api-gateway-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "Base URL for the API Gateway"
  value       = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_url" {
  description = "URL of the Amplify app"
  value       = aws_amplify_app.amplify_app.default_domain
}
