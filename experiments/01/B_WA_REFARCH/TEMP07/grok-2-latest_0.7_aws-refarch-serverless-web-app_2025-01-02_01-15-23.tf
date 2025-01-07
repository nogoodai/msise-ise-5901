terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region for the deployment"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Name of the stack for resource naming"
  default     = "todo-app"
}

variable "application_name" {
  description = "Name of the application for resource naming"
  default     = "todo-app"
}

variable "github_repo" {
  description = "GitHub repository for Amplify app"
  default     = "user/todo-app"
}

# Networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.stack_name}-vpc"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name        = "${var.stack_name}-public-subnet"
    Environment = "production"
    Project     = var.application_name
  }
}

# Authentication
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
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  generate_secret     = false
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls        = ["https://${var.application_name}.${var.stack_name}.com"]
  logout_urls          = ["https://${var.application_name}.${var.stack_name}.com"]

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# Database
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
    Environment = "production"
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-todo-api"
  description = "Todo API for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-todo-api"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.stack_name}-todo-api-deployment"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_stage" "todo_api_stage" {
  deployment_id = aws_api_gateway_deployment.todo_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format          = "$context.identity.sourceIp $context.requestTime $context.httpMethod $context.resourcePath $context.protocol $context.status $context.responseLength $context.requestId"
  }

  tags = {
    Name        = "${var.stack_name}-todo-api-stage"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_usage_plan" "todo_api_usage_plan" {
  name         = "${var.stack_name}-todo-api-usage-plan"
  description  = "Usage plan for ${var.application_name} API"
  product_code = "TODOAPI"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_stage.todo_api_stage.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.stack_name}-todo-api-usage-plan"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.stack_name}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.todo_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_method_settings" "todo_api_method_settings" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = aws_api_gateway_stage.todo_api_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename         = "lambda_functions/add_item.zip"
  function_name    = "${var.stack_name}-add-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/add_item.zip")

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename         = "lambda_functions/get_item.zip"
  function_name    = "${var.stack_name}-get-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/get_item.zip")

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename         = "lambda_functions/get_all_items.zip"
  function_name    = "${var.stack_name}-get-all-items"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/get_all_items.zip")

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename         = "lambda_functions/update_item.zip"
  function_name    = "${var.stack_name}-update-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/update_item.zip")

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename         = "lambda_functions/complete_item.zip"
  function_name    = "${var.stack_name}-complete-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/complete_item.zip")

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-complete-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename         = "lambda_functions/delete_item.zip"
  function_name    = "${var.stack_name}-delete-item"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  source_code_hash = filebase64sha256("lambda_functions/delete_item.zip")

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = "production"
    Project     = var.application_name
  }
}

# API Gateway Lambda Integration
resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.add_item.invoke_arn
}

resource "aws_lambda_permission" "post_item_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/${aws_api_gateway_method.post_item.http_method}${aws_api_gateway_resource.item.path}"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_resource" "item_id" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_resource.item.id
  path_part   = "{id}"
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.item_id.id
  http_method             = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_item.invoke_arn
}

resource "aws_lambda_permission" "get_item_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/${aws_api_gateway_method.get_item.http_method}${aws_api_gateway_resource.item_id.path}"
}

resource "aws_api_gateway_method" "get_all_items" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "get_all_items_integration" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.get_all_items.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_all_items.invoke_arn
}

resource "aws_lambda_permission" "get_all_items_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_all_items.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/${aws_api_gateway_method.get_all_items.http_method}${aws_api_gateway_resource.item.path}"
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "put_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.item_id.id
  http_method             = aws_api_gateway_method.put_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.update_item.invoke_arn
}

resource "aws_lambda_permission" "put_item_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/${aws_api_gateway_method.put_item.http_method}${aws_api_gateway_resource.item_id.path}"
}

resource "aws_api_gateway_method" "complete_item" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "complete_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.item_id.id
  http_method             = aws_api_gateway_method.complete_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.complete_item.invoke_arn
}

resource "aws_lambda_permission" "complete_item_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.complete_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/${aws_api_gateway_method.complete_item.http_method}${aws_api_gateway_resource.item_id.path}/done"
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  resource_id   = aws_api_gateway_resource.item_id.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.todo_api.id
  resource_id             = aws_api_gateway_resource.item_id.id
  http_method             = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.delete_item.invoke_arn
}

resource "aws_lambda_permission" "delete_item_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/${aws_api_gateway_method.delete_item.http_method}${aws_api_gateway_resource.item_id.path}"
}

# Amplify
resource "aws_amplify_app" "todo_app" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo

  build_spec = <<-EOT
    version: 0.1
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT

  tags = {
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"
  framework   = "React"
  stage       = "PRODUCTION"

  environment_variables = {
    REACT_APP_API_URL = aws_api_gateway_stage.todo_api_stage.invoke_url
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-master-branch"
    Environment = "production"
    Project     = var.application_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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

  tags = {
    Name        = "${var.stack_name}-api-gateway-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.stack_name}-api-gateway-policy"
  role = aws_iam_role.api_gateway_role.id

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
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
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

  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

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

  tags = {
    Name        = "${var.stack_name}-lambda-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.stack_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Monitoring and Alerting
resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/api-gateway/${var.stack_name}-todo-api"
  retention_in_days = 30

  tags = {
    Name        = "${var.stack_name}-api-gw-logs"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.stack_name}-lambda-error-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.add_item.function_name
  }

  tags = {
    Name        = "${var.stack_name}-lambda-error-alarm"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_cpu_utilization_alarm" {
  alarm_name          = "${var.stack_name}-lambda-cpu-utilization-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CpuUtilization"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors Lambda function CPU utilization"
  alarm_actions       = []

  dimensions = {
    FunctionName = aws_lambda_function.add_item.function_name
  }

  tags = {
    Name        = "${var.stack_name}-lambda-cpu-utilization-alarm"
    Environment = "production"
    Project     = var.application_name
  }
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.todo_api_stage.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.todo_app.default_domain
}
