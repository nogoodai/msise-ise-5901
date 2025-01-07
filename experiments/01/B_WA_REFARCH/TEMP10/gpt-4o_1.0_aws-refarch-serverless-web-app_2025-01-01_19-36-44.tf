terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the deployment stack."
  default     = "my-app"
}

variable "github_token" {
  description = "GitHub token for Amplify source connection."
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-app-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret = false

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.stack_name}-app-client"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_dynamodb_table" "todo_table" {
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.stack_name}-api-stage"
    Environment = "production"
    Project     = "serverless-web-app"
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
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_api_gateway_rest_api.api.id
  authorizer_type  = "COGNITO_USER_POOLS"
  name             = "${var.stack_name}-cognito-authorizer"
  identity_source  = ["$request.header.Authorization"]
  provider_arns    = [aws_cognito_user_pool.user_pool.arn]

  tags = {
    Name        = "${var.stack_name}-cognito-authorizer"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "crud_lambda" {
  for_each = {
    add_item      = "add-item"
    get_item      = "get-item"
    get_all_items = "get-all-items"
    update_item   = "update-item"
    complete_item = "complete-item"
    delete_item   = "delete-item"
  }

  function_name = "${var.stack_name}-${each.value}"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-${each.value}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_permission" "apigw_permission" {
  for_each = {
    add_item      = "add-item"
    get_item      = "get-item"
    get_all_items = "get-all-items"
    update_item   = "update-item"
    complete_item = "complete-item"
    delete_item   = "delete-item"
  }

  statement_id  = "${each.value}-permission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud_lambda[each.key].function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_amplify_app" "amplify_app" {
  name  = "${var.stack_name}-amplify-app"
  repository = "https://github.com/your-repo/your-app"

  oauth_token = var.github_token
  
  build_spec = <<EOF
version: 1
backend:
  phases:
    build:
      commands:
        - npm install
        - npm run build
    artifacts:
      baseDirectory: /build
      files:
        - '**/*'
branches:
  master:
    stage: PROD
EOF

  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"
  stage = "PROD"
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gw-role"

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
    Name        = "${var.stack_name}-api-gw-role"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.stack_name}-api-gw-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

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
    Name        = "${var.stack_name}-lambda-exec-role"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.stack_name}-lambda-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:*"
        ],
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:*"
        ],
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${aws_lambda_function.crud_lambda.*.function_name}*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "api_gateway_url" {
  description = "Invoke URL of the API Gateway"
  value       = "${aws_api_gateway_rest_api.api.execution_arn}/prod/"
}

output "amplify_app_id" {
  description = "ID of the Amplify App"
  value       = aws_amplify_app.amplify_app.id
}
