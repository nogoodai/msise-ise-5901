terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Application stack name"
  default     = "my-app"
}

variable "project_name" {
  description = "Project name for tagging"
  default     = "serverless-web-app"
}

variable "environment" {
  description = "Deployment environment"
  default     = "production"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-${var.stack_name}"

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
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.project_name}-user-pool-client"

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
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

  provisioned_throughput {
    read_capacity_units  = 5
    write_capacity_units = 5
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-dynamodb-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_apigatewayv2_api" "api_gateway" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
  }

  tags = {
    Name        = "${var.project_name}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id = aws_apigatewayv2_api.api_gateway.id
  name   = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format          = jsonencode({
      requestId = "$context.requestId",
      ip        = "$context.identity.sourceIp",
      caller    = "$context.identity.caller",
      user      = "$context.identity.user"
    })
  }

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  tags = {
    Name        = "${var.project_name}-api-stage"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name = "/aws/apigateway/${var.project_name}-${var.stack_name}"

  retention_in_days = 7

  tags = {
    Name        = "${var.project_name}-api-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id       = aws_apigatewayv2_api.api_gateway.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name         = "cognito-authorizer"
  
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = aws_cognito_user_pool.user_pool.endpoint
  }
}

resource "aws_lambda_function" "crud_operations" {
  for_each = {
    AddItem:    "POST /item",
    GetItem:    "GET /item/{id}",
    GetAllItems: "GET /item",
    UpdateItem:  "PUT /item/{id}",
    CompleteItem: "POST /item/{id}/done",
    DeleteItem:  "DELETE /item/{id}"
  }

  function_name = "${var.project_name}-${each.key}"

  runtime      = "nodejs12.x"
  handler      = "index.handler"
  memory_size  = 1024
  timeout      = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.project_name}-lambda-${each.key}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-execution-role"

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
    Name        = "${var.project_name}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name   = "${var.project_name}-lambda-dynamodb-policy"
  role   = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_cw_policy" {
  name   = "${var.project_name}-lambda-cloudwatch-policy"
  role   = aws_iam_role.lambda_execution_role.id

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
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.project_name}-amplify-app"

  repository = "https://github.com/yourrepo"

  build_spec = jsonencode({
    version = 0.1
    phases = {
      install = {
        commands = ["npm install"]
      }
      build = {
        commands = ["npm run build"]
      }
    }
    artifacts = {
      baseDirectory = "build"
      files = ["**/*"]
    }
  })

  tags = {
    Name        = "${var.project_name}-amplify-app"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"

  enable_auto_build = true

  tags = {
    Name        = "${var.project_name}-amplify-branch"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-api-gateway-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "api_gateway_logging_policy" {
  name = "${var.project_name}-api-gateway-logging-policy"
  role = aws_iam_role.api_gateway_role.id

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
}

resource "aws_iam_role" "amplify_execution_role" {
  name = "${var.project_name}-amplify-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_endpoint" {
  value = aws_apigatewayv2_api.api_gateway.api_endpoint
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
