terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = "us-east-1"
}

variable "stack_name" {
  default = "my-app-stack"
}

variable "environment" {
  default = "production"
}

variable "project_name" {
  default = "serverless-web-app"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.project_name}-${var.stack_name}-client"

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain      = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  
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

  provisioned_throughput {
    read_capacity_units  = 5
    write_capacity_units = 5
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-${var.stack_name}-api"
  description = "API for ${var.project_name}"

  endpoint_configuration {
    types = ["EDGE"]
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-api-stage"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.project_name}-${var.stack_name}-usage-plan"

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
    Name        = "${var.project_name}-${var.stack_name}-usage-plan"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "add_item_function" {
  filename         = "path/to/your/package.zip"
  function_name    = "add-item-function"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "add-item-function"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item_function.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_amplify_app" "amplify_app" {
  name                = "${var.project_name}-${var.stack_name}-app"
  repository          = "https://github.com/your-username/your-repo.git"
  oauth_token         = "github-oauth-token"

  build_spec = file("amplify-build-spec.yml")

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-app"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id     = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-amplify-branch"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
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
    Name        = "${var.project_name}-${var.stack_name}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB Table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "Invoke URL for the API Gateway"
  value       = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  description = "ID of the Amplify App"
  value       = aws_amplify_app.amplify_app.id
}
