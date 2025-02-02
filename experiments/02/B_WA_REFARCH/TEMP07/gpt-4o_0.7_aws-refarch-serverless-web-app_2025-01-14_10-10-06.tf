terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name for naming resources."
  type        = string
  default     = "prod"
}

# Cognito Resources
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
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.stack_name}-user-pool-client"

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  generate_secret           = false
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-${var.app_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
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
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = jsonencode({
    "swagger": "2.0",
    "info": {
      "title": "${var.stack_name} API"
    },
    "paths": {
      "/item": {
        "get": {
          "x-amazon-apigateway-integration": {
            "uri": "${aws_lambda_function.get_all_items.invoke_arn}",
            "httpMethod": "POST",
            "type": "AWS_PROXY"
          },
          "responses": {
            "200": {
              "description": "200 response"
            }
          }
        },
        "post": {
          "x-amazon-apigateway-integration": {
            "uri": "${aws_lambda_function.add_item.invoke_arn}",
            "httpMethod": "POST",
            "type": "AWS_PROXY"
          },
          "responses": {
            "200": {
              "description": "200 response"
            }
          }
        }
      },
      "/item/{id}": {
        "get": {
          "x-amazon-apigateway-integration": {
            "uri": "${aws_lambda_function.get_item.invoke_arn}",
            "httpMethod": "POST",
            "type": "AWS_PROXY"
          },
          "responses": {
            "200": {
              "description": "200 response"
            }
          }
        },
        "put": {
          "x-amazon-apigateway-integration": {
            "uri": "${aws_lambda_function.update_item.invoke_arn}",
            "httpMethod": "POST",
            "type": "AWS_PROXY"
          },
          "responses": {
            "200": {
              "description": "200 response"
            }
          }
        },
        "delete": {
          "x-amazon-apigateway-integration": {
            "uri": "${aws_lambda_function.delete_item.invoke_arn}",
            "httpMethod": "POST",
            "type": "AWS_PROXY"
          },
          "responses": {
            "200": {
              "description": "200 response"
            }
          }
        },
        "post": {
          "x-amazon-apigateway-integration": {
            "uri": "${aws_lambda_function.complete_item.invoke_arn}",
            "httpMethod": "POST",
            "type": "AWS_PROXY"
          },
          "responses": {
            "200": {
              "description": "200 response"
            }
          }
        }
      }
    }
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format          = "$context.identity.sourceIp"
  }

  xray_tracing_enabled = true
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api))
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name} API"

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

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename         = "path/to/lambda.zip"
  function_name    = "${var.stack_name}-add-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  publish          = true

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "get_item" {
  filename         = "path/to/lambda.zip"
  function_name    = "${var.stack_name}-get-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  publish          = true

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename         = "path/to/lambda.zip"
  function_name    = "${var.stack_name}-get-all-items"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  publish          = true

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "update_item" {
  filename         = "path/to/lambda.zip"
  function_name    = "${var.stack_name}-update-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  publish          = true

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "complete_item" {
  filename         = "path/to/lambda.zip"
  function_name    = "${var.stack_name}-complete-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  publish          = true

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "delete_item" {
  filename         = "path/to/lambda.zip"
  function_name    = "${var.stack_name}-delete-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  publish          = true

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }
}

# Amplify Resources
resource "aws_amplify_app" "amplify_app" {
  name              = "${var.stack_name}-amplify"
  repository        = "https://github.com/user/repo"
  oauth_token       = var.github_token
  build_spec        = file("buildspec.yml")

  environment_variables = {
    _LIVE_UPDATES = "true"
  }

  auto_branch_creation {
    enable_auto_build = true
    patterns          = ["master"]
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
          "Service": "amplify.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_full_access" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/api-gateway/${var.stack_name}"
  retention_in_days = 14
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table."
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_endpoint" {
  description = "The endpoint URL for the API Gateway."
  value       = aws_api_gateway_rest_api.api.execution_arn
}

output "amplify_app_id" {
  description = "The ID of the Amplify app."
  value       = aws_amplify_app.amplify_app.id
}
