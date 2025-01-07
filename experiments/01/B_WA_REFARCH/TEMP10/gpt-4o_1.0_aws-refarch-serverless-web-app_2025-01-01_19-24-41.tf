terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.4.0"
}

provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  description = "The name of the project"
  type        = string
  default     = "serverless-web-app"
}

variable "environment" {
  description = "The environment for deployment"
  type        = string
  default     = "prod"
}

variable "github_repo" {
  description = "GitHub repository for Amplify"
  type        = string
  default     = "user/repo"
}

variable "custom_domain_name" {
  description = "Custom domain name for Cognito"
  type        = string
  default     = "auth.${var.project_name}.com"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.project_name}-user-pool"

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
  }

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
  name                   = "${var.project_name}-user-pool-client"
  user_pool_id           = aws_cognito_user_pool.user_pool.id
  generate_secret        = false
  allowed_oauth_flows    = ["authorization_code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = var.custom_domain_name
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.environment}"
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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.project_name}-api"
  description = "API Gateway for ${var.project_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.project_name}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_resource" "resource_items" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  path_part   = "item"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id

  tags = {
    Name        = "items"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource_items.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"

  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.project_name}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300

  tags = {
    Name        = "${var.project_name}-cognito-authorizer"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_stage" "prod_stage" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  tags = {
    Name        = "${var.project_name}-prod-stage"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.project_name}-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod_stage.stage_name
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
    Name        = "${var.project_name}-usage-plan"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "add_item_function" {
  function_name = "${var.project_name}-add-item"
  handler       = "addItem.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project_name}-add-item"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ],
  })

  tags = {
    Name        = "${var.project_name}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:*",
          "cloudwatch:*",
          "xray:*"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ],
  })

  tags = {
    Name        = "${var.project_name}-lambda-policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.project_name}-app"

  source_code {
    repository_url = "https://github.com/${var.github_repo}"
    branch_name    = "master"
    auto_build     = true
  }

  build_spec = <<-DOC
    version: 1.0
    frontend:
      phases:
        build:
          commands:
            - npm install
            - npm run build
     artifacts:
        baseDirectory: /build
        files:
          - '**/*'
    DOC

  tags = {
    Name        = "${var.project_name}-app"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ],
  })

  tags = {
    Name        = "${var.project_name}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_iam_policy" "amplify_policy" {
  name = "${var.project_name}-amplify-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "amplify:*"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ],
  })
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ],
  })

  tags = {
    Name        = "${var.project_name}-api-gateway-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_policy" "api_gateway_policy" {
  name = "${var.project_name}-api-gateway-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:*"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ],
  })
}

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "DynamoDB Table Name"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_api_gateway_rest_api.api.id
}

output "lambda_function_arn" {
  description = "Lambda Function ARN"
  value       = aws_lambda_function.add_item_function.arn
}

output "amplify_app_id" {
  description = "Amplify App ID"
  value       = aws_amplify_app.amplify_app.id
}
