terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_token" {
  type = string
}

# Cognito Resources
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verify_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.stack_name
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-client"

  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows  = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  generate_secret = false
  
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# DynamoDB Resources
resource "aws_dynamodb_table" "todo_table" {
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
  }
}

# API Gateway Resources
resource "aws_api_gateway_rest_api" "main" {
  name = "${var.stack_name}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "main" {
  name          = "CognitoUserPoolAuthorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
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

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Functions and IAM Roles
resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Lambda Functions
locals {
  lambda_functions = {
    add_item = {
      handler = "index.addItem"
      http_method = "POST"
      path = "/item"
    }
    get_item = {
      handler = "index.getItem"
      http_method = "GET" 
      path = "/item/{id}"
    }
    get_all_items = {
      handler = "index.getAllItems"
      http_method = "GET"
      path = "/item"
    }
    update_item = {
      handler = "index.updateItem"
      http_method = "PUT"
      path = "/item/{id}"
    }
    complete_item = {
      handler = "index.completeItem"
      http_method = "POST"
      path = "/item/{id}/done"
    }
    delete_item = {
      handler = "index.deleteItem"
      http_method = "DELETE"
      path = "/item/{id}"
    }
  }
}

resource "aws_lambda_function" "functions" {
  for_each = local.lambda_functions

  filename         = "lambda.zip"
  function_name    = "${var.stack_name}-${each.key}"
  role            = aws_iam_role.lambda_role.arn
  handler         = each.value.handler
  runtime         = "nodejs12.x"
  memory_size     = 1024
  timeout         = 60

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-${each.key}"
    Environment = "prod"
  }
}

# Amplify Resources
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

resource "aws_amplify_app" "main" {
  name = var.stack_name
  repository = var.github_repo
  access_token = var.github_token

  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        build:
          commands:
            - npm ci
            - npm run build
      artifacts:
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  enable_auto_branch_creation = true
  enable_branch_auto_build = true

  iam_service_role_arn = aws_iam_role.amplify_role.arn
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
  
  enable_auto_build = true
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambda_functions

  alarm_name          = "${var.stack_name}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name        = "Errors"
  namespace          = "AWS/Lambda"
  period             = "300"
  statistic          = "Sum"
  threshold          = "0"
  alarm_description  = "Lambda function error rate"
  
  dimensions = {
    FunctionName = aws_lambda_function.functions[each.key].function_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "api_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}"
}

output "amplify_app_url" {
  value = "https://${aws_amplify_branch.master.branch_name}.${aws_amplify_app.main.id}.amplifyapp.com"
}
