terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack."
  default     = "my-app"
}

variable "github_repository" {
  description = "GitHub repository URL for Amplify."
  default     = "https://github.com/user/my-app"
}

resource "aws_cognito_user_pool" "main" {
  name                      = "${var.stack_name}-user-pool"
  auto_verified_attributes  = ["email"]
  username_attributes       = ["email"]
  password_policy {
    minimum_length       = 6
    require_uppercase    = true
    require_lowercase    = true
    require_numbers      = false
    require_symbols      = false
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                        = "${var.stack_name}-user-pool-client"
  user_pool_id                = aws_cognito_user_pool.main.id
  generate_secret             = false
  allowed_oauth_flows         = ["code", "implicit"]
  allowed_oauth_scopes        = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "cognito-username"
  range_key      = "id"

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

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "${var.stack_name}-cognito-authorizer"
  type                   = "COGNITO_USER_POOLS"
  rest_api_id            = aws_api_gateway_rest_api.main.id
  identity_source        = "method.request.header.Authorization"
  provider_arns          = [aws_cognito_user_pool.main.arn]
}

resource "aws_api_gateway_stage" "prod" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.main.id
  deployment_id        = aws_api_gateway_deployment.main.id
  xray_tracing_enabled = true
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  depends_on  = [aws_api_gateway_method.any, aws_api_gateway_authorizer.cognito]
}

resource "aws_api_gateway_method" "any" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_rest_api.main.root_resource_id
  http_method   = "ANY"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"
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

resource "aws_lambda_function" "crud" {
  for_each      = toset(["add-item", "get-item", "get-all-items", "update-item", "complete-item", "delete-item"])
  function_name = "${var.stack_name}-${each.key}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo.name
    }
  }
}

resource "aws_amplify_app" "main" {
  name              = "${var.stack_name}-amplify"
  repository        = var.github_repository
  oauth_token       = var.github_oauth_token

  auto_branch_creation_config {
    enable_auto_build = true
  }

  environment_variables = {
    ENVIRONMENT = "prod"
  }
}

resource "aws_amplify_branch" "main" {
  app_id              = aws_amplify_app.main.id
  branch_name         = "master"
  enable_auto_build   = true
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec"
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
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role" "apigateway_role" {
  name = "${var.stack_name}-apigateway-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apigateway_policy" {
  role       = aws_iam_role.apigateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSAmplifyConsoleFullAccess"
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.todo.name
}

output "amplify_app_id" {
  description = "The ID of the Amplify app."
  value       = aws_amplify_app.main.id
}
