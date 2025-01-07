terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack"
}

variable "github_repository" {
  description = "GitHub repository for Amplify app source"
}

variable "github_branch" {
  description = "GitHub branch for Amplify app"
  default     = "master"
}

resource "aws_cognito_user_pool" "main" {
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
  }
}

resource "aws_cognito_user_pool_client" "client" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "${var.stack_name}-user-pool-client"
  generate_secret = false
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls = ["https://yourapp.com/callback"]
  
  tags = {
    Name = "${var.stack_name}-user-pool-client"
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.stack_name}-${var.stack_name}-app"
  user_pool_id = aws_cognito_user_pool.main.id
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
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
  }
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name = "${var.stack_name}-api-gateway"
  
  tags = {
    Name = "${var.stack_name}-api-gateway"
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.todo_api.id
  deployment_id        = aws_api_gateway_deployment.prod.id
  cache_cluster_enabled = false

  tags = {
    Name = "${var.stack_name}-api-gateway-prod-stage"
  }
}

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  triggers = {
    redeployment = sha1(jsonencode(aws_lambda_function.todo_lambda.*.qualified_arn))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "todo_plan" {
  name = "${var.stack_name}-usage-plan"
  
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
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

  tags = {
    Name = "${var.stack_name}-api-usage-plan"
  }
}

resource "aws_lambda_function" "todo_lambda" {
  function_name = "${var.stack_name}-lambda-function"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = "path-to-your-lambda-code.zip"

  handler = "index.handler"
  runtime = "nodejs12.x"

  memory_size     = 1024
  timeout         = 60
  role            = aws_iam_role.lambda_exec_role.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name = "${var.stack_name}-lambda"
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_lambda.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

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
    Name = "${var.stack_name}-lambda-exec-role"
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.stack_name}-lambda-policy"
  role   = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = "cloudwatch:PutMetricData"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "frontend_app" {
  name = "${var.stack_name}-amplify-app"
  repository = var.github_repository
  
  build_spec = file("buildspec.yml")

  oauth_token = var.github_token

  enable_auto_branch_creation = true

  tags = {
    Name = "${var.stack_name}-amplify-app"
  }
}

resource "aws_amplify_branch" "main" {
  branch_name   = var.github_branch
  app_id        = aws_amplify_app.frontend_app.id
  enable_auto_build = true

  tags = {
    Name = "${var.stack_name}-amplify-branch"
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.stack_name}-amplify-role"
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["amplify:*"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.todo_api.execution_arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "amplify_app_arn" {
  value = aws_amplify_app.frontend_app.arn
}
