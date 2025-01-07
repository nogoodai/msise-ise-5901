terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "stack_name" {
  default = "my-app-stack"
}

resource "aws_cognito_user_pool" "auth" {
  name          = "${var.stack_name}-user-pool"
  auto_verified_attributes = ["email"]

  policies {
    password_policy {
      minimum_length    = 6
      require_uppercase = true
      require_lowercase = true
      require_symbols   = false
      require_numbers   = false
    }
  }
}

resource "aws_cognito_user_pool_client" "auth" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.auth.id
  generate_secret = false
  o_auth_flows {
    authorization_code_grant = true
    implicit = true
  }
  allowed_o_auth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "auth" {
  domain      = "${var.stack_name}-auth-domain"
  user_pool_id = aws_cognito_user_pool.auth.id
}

resource "aws_dynamodb_table" "todo" {
  name           = "todo-table-${var.stack_name}"
  hash_key       = "cognito-username"
  range_key      = "id"
  billing_mode   = "PROVISIONED"
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
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-api"
  description = "API for managing to-do items"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  deployment_id = aws_api_gateway_deployment.todo_deployment.id

  method_settings {
    http_method = "*"
    resource_path = "/*"
    logging_level = "INFO"
    metrics_enabled = true
    data_trace_enabled = true
  }
}

resource "aws_api_gateway_usage_plan" "basic" {
  name = "Basic"
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
}

resource "aws_api_gateway_authorizer" "cognito_auth" {
  name                = "CognitoAuthorizer"
  rest_api_id         = aws_api_gateway_rest_api.todo_api.id
  type                = "COGNITO_USER_POOLS"
  identity_source     = "method.request.header.Authorization"
  provider_arns       = [aws_cognito_user_pool.auth.arn]
}

resource "aws_lambda_function" "add_item" {
  filename         = "add_item.zip"
  function_name    = "add-item-function"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo.name
    }
  }
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/POST/item"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_execution_role"

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
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.add_item.function_name}"
  retention_in_days = 7
}

resource "aws_amplify_app" "frontend" {
  name              = "${var.stack_name}-frontend"
  repository        = "https://github.com/example/repo"
  oauth_token       = var.github_token

  build_spec = jsonencode({
    version = 1
    frontend = {
      phases = {
        preBuild = {
          commands = ["npm install"]
        }
        build = {
          commands = ["npm run build"]
        }
      }
      artifacts = {
        baseDirectory = "/build"
        files = ["**/*"]
      }
      cache = {
        paths = ["node_modules/**/*"]
      }
    }
  })
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "master"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.auth.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.todo_deployment.invoke_url
}
