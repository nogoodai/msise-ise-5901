terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack"
  type        = string
  default     = "prod"
}

variable "github_repository" {
  description = "GitHub repository URL for Amplify app"
  type        = string
  default     = "https://github.com/your-repo/example"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "app" {
  name                   = "${var.stack_name}-app-client"
  user_pool_id           = aws_cognito_user_pool.main.id
  generate_secret        = false
  allowed_oauth_flows    = ["code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "main" {
  domain      = "auth-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
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
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-todo-api"
  description = "API for TODO application."

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  gateway_response {
    type = "DEFAULT_4XX"
    response_parameters = {
      "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
      "gatewayresponse.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,OPTIONS,DELETE'"
      "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    }
    response_type = "DEFAULT_4XX"
    status_code   = "401"
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.todo.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = "prod"

  tags = {
    Name        = "${var.stack_name}-prod-stage"
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

// Additional Lambda functions (get_item, get_all_items, update_item, complete_item, delete_item) configuration...

resource "aws_amplify_app" "frontend" {
  name                = "${var.stack_name}-amplify-app"
  repository          = var.github_repository

  auto_branch_creation_config {
    basic_auth_config {
      enable_basic_auth = false
    }
  }

  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

resource "aws_amplify_branch" "main" {
  app_id     = aws_amplify_app.frontend.id
  branch_name = "master"

  framework = "React" // specify the framework being used

  tags = {
    Name        = "${var.stack_name}-amplify-master-branch"
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec-role"

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
    Environment = var.stack_name
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_crud_dynamodb" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.add_item.function_name}"
  retention_in_days = 30
}

output "api_gateway_url" {
  description = "Base URL for API Gateway"
  value       = "${aws_api_gateway_rest_api.todo_api.execution_arn}/prod"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
