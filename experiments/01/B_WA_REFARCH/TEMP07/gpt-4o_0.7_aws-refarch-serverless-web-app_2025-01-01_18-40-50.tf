terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-west-2"
}

variable "stack_name" {
  default = "my-stack"
}

variable "application_name" {
  default = "my-app"
}

variable "github_repo" {
  description = "GitHub repository URL for Amplify"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-user-pool"

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain        = "${var.application_name}-${var.stack_name}"
  user_pool_id  = aws_cognito_user_pool.user_pool.id
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.application_name}-user-pool-client"

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  generate_secret            = false

  tags = {
    Name        = "${var.application_name}-user-pool-client"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"

  hash_key       = "cognito-username"
  range_key      = "id"

  read_capacity  = 5
  write_capacity = 5

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
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api"
  description = "API Gateway for ${var.application_name}"

  tags = {
    Name        = "${var.application_name}-api"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.items.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_auth.id
}

resource "aws_api_gateway_authorizer" "cognito_auth" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_method.get_item
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
  
  tags = {
    Name        = "${var.application_name}-api-stage"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.application_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.api_stage.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_lambda_function" "crud_operations" {
  function_name = "${var.application_name}-crud"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.application_name}-crud-lambda"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.crud_operations.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.application_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "sts:AssumeRole"
      Effect   = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.application_name}-lambda-exec-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_logging_policy" {
  name   = "${var.application_name}-lambda-logging-policy"
  role   = aws_iam_role.lambda_exec_role.id
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
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name   = "${var.application_name}-dynamodb-crud-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_amplify_app" "frontend" {
  name  = "${var.application_name}-amplify"
  repository = var.github_repo

  build_spec = jsonencode({
    version = "1.0"
    applications = [{
      frontend = "javascript"
      framework = "react"
      environment_variables = {
        ENV_VAR_EXAMPLE = "value"
      }
      source_directory = "/"
      build_command    = "npm run build"
      start_command    = "npm start"
    }]
  })

  tags = {
    Name        = "${var.application_name}-amplify"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id        = aws_amplify_app.frontend.id
  branch_name   = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-amplify-branch-master"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "sts:AssumeRole"
      Effect   = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.application_name}-api-gateway-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_logging_policy" {
  name   = "${var.application_name}-api-gateway-logging-policy"
  role   = aws_iam_role.api_gateway_role.id
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
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "sts:AssumeRole"
      Effect   = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.application_name}-amplify-role"
    Environment = "prod"
    Project     = var.application_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.api_stage.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
