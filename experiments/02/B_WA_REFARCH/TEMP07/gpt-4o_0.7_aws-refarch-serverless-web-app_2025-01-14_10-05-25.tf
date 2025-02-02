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
  description = "The AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name to uniquely identify resources."
  type        = string
  default     = "prod"
}

variable "github_repo" {
  description = "The GitHub repository for Amplify source."
  type        = string
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }
  
  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
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
    Environment = var.stack_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = var.stack_name
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda-dynamodb-policy-${var.stack_name}"
  description = "Policy for Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow"
        Action = "cloudwatch:PutMetricData"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_lambda_function" "crud_functions" {
  for_each = {
    add    = "POST /item"
    get    = "GET /item/{id}"
    getAll = "GET /item"
    update = "PUT /item/{id}"
    done   = "POST /item/{id}/done"
    delete = "DELETE /item/{id}"
  }

  function_name = "${each.key}-function-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role = aws_iam_role.lambda_exec_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${each.key}-function-${var.stack_name}"
    Environment = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = "api-gateway-${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "api-gateway-${var.stack_name}"
    Environment = var.stack_name
  }
}

resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "crud_methods" {
  for_each = {
    add    = "POST"
    get    = "GET"
    getAll = "GET"
    update = "PUT"
    done   = "POST"
    delete = "DELETE"
  }

  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.items.id
  http_method = each.value
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_user_pool_authorizer.id

  request_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_authorizer" "cognito_user_pool_authorizer" {
  name = "cognito-authorizer-${var.stack_name}"
  rest_api_id = aws_api_gateway_rest_api.api.id
  type = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  tags = {
    Name        = "api-stage-${var.stack_name}"
    Environment = var.stack_name
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_method.crud_methods
  ]
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "usage-plan-${var.stack_name}"

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
}

resource "aws_iam_role" "api_gateway_exec_role" {
  name = "api-gateway-exec-role-${var.stack_name}"

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
    Name        = "api-gateway-exec-role-${var.stack_name}"
    Environment = var.stack_name
  }
}

resource "aws_iam_policy" "api_gateway_cw_policy" {
  name        = "api-gateway-cw-policy-${var.stack_name}"
  description = "Policy for API Gateway to log to CloudWatch"

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

resource "aws_iam_role_policy_attachment" "api_gateway_cw_policy_attach" {
  role       = aws_iam_role.api_gateway_exec_role.name
  policy_arn = aws_iam_policy.api_gateway_cw_policy.arn
}

resource "aws_amplify_app" "amplify" {
  name = "amplify-app-${var.stack_name}"

  repository = var.github_repo
  branch     = "master"

  build_spec = filebase64("${path.module}/buildspec.yml")

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.stack_name
  }
}

resource "aws_iam_role" "amplify_exec_role" {
  name = "amplify-exec-role-${var.stack_name}"

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
    Name        = "amplify-exec-role-${var.stack_name}"
    Environment = var.stack_name
  }
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_arn" {
  description = "The ARN of the DynamoDB table."
  value       = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_url" {
  description = "The URL of the API Gateway endpoint."
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "amplify_app_id" {
  description = "The ID of the Amplify app."
  value       = aws_amplify_app.amplify.id
}
