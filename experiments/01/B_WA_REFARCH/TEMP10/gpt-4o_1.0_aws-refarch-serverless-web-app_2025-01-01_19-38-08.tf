terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy into"
  default     = "us-west-2"
}

variable "stack_name" {
  description = "The stack name to use for naming resources"
  default     = "myapp"
}

variable "cognito_domain_prefix" {
  description = "The prefix for the Cognito custom domain"
  default     = "myapp-auth"
}

variable "github_repository" {
  description = "GitHub repository to source the Amplify application"
  default     = "user/repository"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]
  
  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "cognito-user-pool"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                   = "${var.stack_name}-client"
  user_pool_id           = aws_cognito_user_pool.user_pool.id
  generate_secret        = false
  allowed_oauth_flows    = ["code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "cognito-user-pool-client"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain       = "${var.cognito_domain_prefix}-${var.stack_name}"
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

  provisioned_throughput {
    read_capacity_units  = 5
    write_capacity_units = 5
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_api" "api_gateway" {
  name          = "${var.stack_name}-api"
  protocol_type = "HTTP"

  tags = {
    Name        = "api-gateway"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id = aws_apigatewayv2_api.api_gateway.id
  name   = "prod"
  auto_deploy = true
  
  tags = {
    Name        = "api-gateway-stage"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id = aws_apigatewayv2_api.api_gateway.id
  name   = "${var.stack_name}-cognito-auth"
  identity_source = ["$request.header.Authorization"]
  authorizer_type = "JWT"
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = aws_cognito_user_pool.user_pool.endpoint
  }

  tags = {
    Name        = "cognito-authorizer"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "crud_lambda" {
  function_name = "${var.stack_name}-crud"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  xray_tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "crud-lambda"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.crud_lambda.function_name}"
  retention_in_days = 7

  tags = {
    Name        = "lambda-log-group"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.stack_name}-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "lambda-execution-role"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "apigateway_logging_role" {
  name = "${var.stack_name}-api-gw-logging"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "api-gw-logging-role"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_dynamodb" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_policy_cw_logs" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_amplify_app" "app" {
  name = "${var.stack_name}-frontend"

  source_code_repository = var.github_repository
  branch                 = "master"

  tags = {
    Name        = "amplify-app"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_permission" "allow_apigateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud_lambda.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = join("", [aws_apigatewayv2_api.api_gateway.execution_arn, "/*"])
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_endpoint" {
  description = "The endpoint of the API Gateway"
  value       = aws_apigatewayv2_api.api_gateway.api_endpoint
}

output "amplify_app_id" {
  description = "The ID of the Amplify App"
  value       = aws_amplify_app.app.id
}
