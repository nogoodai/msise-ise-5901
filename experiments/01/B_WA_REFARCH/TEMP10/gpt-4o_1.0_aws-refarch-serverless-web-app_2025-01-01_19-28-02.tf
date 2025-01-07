terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  description = "The name of the project"
  default     = "serverless-web-app"
}

variable "environment" {
  description = "Deployment environment"
  default     = "prod"
}

resource "aws_cognito_user_pool" "auth" {
  name = "${var.project_name}-${var.environment}-user-pool"

  auto_verified_attributes = ["email"]

  policies {
    password_policy {
      minimum_length    = 6
      require_lowercase = true
      require_uppercase = true
    }
  }

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "client" {
  user_pool_id = aws_cognito_user_pool.auth.id
  name         = "${var.project_name}-client"
  generate_secret = false

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "openid", "phone"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.project_name}-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain      = "${var.project_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.auth.id

  tags = {
    Name        = "${var.project_name}-domain"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_dynamodb_table" "todo" {
  name         = "${var.project_name}-${var.environment}-todo-table"
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
    Name        = "${var.project_name}-todo-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.environment}-api-gateway-role"

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
    Name        = "${var.project_name}-api-gateway-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.project_name}-${var.environment}-api-gateway-policy"
  description = "Policy for API Gateway to write logs to CloudWatch"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  tags = {
    Name        = "${var.project_name}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = var.environment
  auto_deploy = true

  tags = {
    Name        = "${var.project_name}-api-stage"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "crud" {
  function_name = "${var.project_name}-crud-lambda"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  
  memory_size = 1024
  timeout     = 60

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-crud-lambda"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_amplify_app" "frontend" {
  name                   = "${var.project_name}-frontend"
  repository             = "https://github.com/your-username/${var.project_name}.git"
  oauth_token            = "your-oauth-token"
  build_spec             = file("amplify-build-spec.yml")

  branch {
    branch_name         = "main"
    basic_auth_credentials = "basic-auth-credentials"

    environment_variables = {
      ENV = var.environment
    }

    enable_auto_build = true
  }

  tags = {
    Name        = "${var.project_name}-frontend"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-${var.environment}-lambda-exec-role"

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
    Name        = "${var.project_name}-lambda-exec-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-${var.environment}-lambda-policy"
  description = "Policy for Lambda to access DynamoDB and CloudWatch"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:*",
        ]
        Resource = aws_dynamodb_table.todo.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:*",
          "xray:PutTelemetryRecords",
          "xray:PutTraceSegments"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.auth.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "api_gateway_url" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
