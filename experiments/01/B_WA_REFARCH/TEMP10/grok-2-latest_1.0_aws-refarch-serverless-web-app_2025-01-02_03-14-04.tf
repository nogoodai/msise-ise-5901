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
  description = "The AWS region where resources will be created"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack"
  default     = "todo-app"
}

variable "application_name" {
  description = "The name of the application"
  default     = "todo-app"
}

variable "cognito_domain" {
  description = "The custom domain for Cognito"
  default     = "auth.todo-app.com"
}

variable "github_repo" {
  description = "GitHub repository for Amplify frontend"
  default     = "your-username/your-repo"
}

# Networking

# Compute

# Storage

# Authentication

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length  = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.application_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${var.application_name}.amplifyapp.com/"]
  logout_urls                          = ["https://${var.application_name}.amplifyapp.com/"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.application_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = var.cognito_domain
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name        = "${var.application_name}-user-pool-domain"
    Environment = var.stack_name
    Project     = var.application_name
  }
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
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.application_name}-api"
  description = "API Gateway for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "${var.application_name}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api_gateway.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_deployment" "api_gateway_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api_gateway.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_gateway_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.application_name}-usage-plan"
  description = "Usage plan for ${var.application_name} API"

  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
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

  tags = {
    Name        = "${var.application_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Lambda Functions

locals {
  lambda_functions = [
    {
      name       = "addItem"
      method     = "POST"
      path       = "/item"
      policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
    },
    {
      name       = "getItem"
      method     = "GET"
      path       = "/item/{id}"
      policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
    },
    {
      name       = "getAllItems"
      method     = "GET"
      path       = "/item"
      policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
    },
    {
      name       = "updateItem"
      method     = "PUT"
      path       = "/item/{id}"
      policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
    },
    {
      name       = "completeItem"
      method     = "POST"
      path       = "/item/{id}/done"
      policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
    },
    {
      name       = "deleteItem"
      method     = "DELETE"
      path       = "/item/{id}"
      policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
    },
  ]
}

resource "aws_lambda_function" "lambda_functions" {
  for_each = { for func in local.lambda_functions : func.name => func }

  function_name    = "${var.application_name}-${each.value.name}"
  filename         = "lambda_function_payload.zip"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")
  handler          = "index.handler"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-${each.value.name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-lambda-role"

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
    Name        = "${var.application_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  for_each = { for func in local.lambda_functions : func.name => func }

  role       = aws_iam_role.lambda_role.name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy_attachment" "lambda_logs_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# API Gateway Lambda Integration

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_methods" {
  for_each = { for func in local.lambda_functions : func.name => func }

  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_resource.todo_resource.id
  http_method   = each.value.method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.id" = each.value.path == "/item/{id}" ? true : false
  }
}

resource "aws_api_gateway_integration" "todo_integrations" {
  for_each = { for func in local.lambda_functions : func.name => func }

  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_resource.todo_resource.id
  http_method             = aws_api_gateway_method.todo_methods[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_functions[each.key].invoke_arn
}

resource "aws_lambda_permission" "todo_api_gateway" {
  for_each = { for func in local.lambda_functions : func.name => func }

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_functions[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/${aws_api_gateway_method.todo_methods[each.key].http_method}${aws_api_gateway_resource.todo_resource.path}"
}

# Frontend Hosting with Amplify

resource "aws_amplify_app" "amplify_app" {
  name       = var.application_name
  repository = var.github_repo

  build_spec = <<-EOT
    version: 1
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

  custom_rules = [
    {
      source = "</^((?!\\.(css|gif|ico|jpg|js|png|txt|svg|woff|ttf|map|json)$).)*$/>",
      status = "200",
      target = "/index.html"
    }
  ]

  tags = {
    Name        = var.application_name
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"

  framework = "React"
  stage     = "PRODUCTION"

  environment_variables = {
    REACT_APP_API_URL = aws_api_gateway_stage.prod.invoke_url
  }

  tags = {
    Name        = "${var.application_name}-master-branch"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Roles and Policies

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

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
    Name        = "${var.application_name}-api-gateway-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_logs_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-amplify-role"

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
    Name        = "${var.application_name}-amplify-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_admin_policy" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
}

# Monitoring and Alerting

resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/api-gateway/${var.application_name}-api"
  retention_in_days = 30

  tags = {
    Name        = "${var.application_name}-api-log-group"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors_alarm" {
  alarm_name          = "${var.application_name}-lambda-errors-alarm"
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
    FunctionName = aws_lambda_function.lambda_functions["addItem"].function_name
  }

  tags = {
    Name        = "${var.application_name}-lambda-errors-alarm"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_consumed_read_capacity_alarm" {
  alarm_name          = "${var.application_name}-dynamodb-read-capacity-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ConsumedReadCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors DynamoDB consumed read capacity units"
  alarm_actions       = []

  dimensions = {
    TableName = aws_dynamodb_table.todo_table.name
  }

  tags = {
    Name        = "${var.application_name}-dynamodb-read-capacity-alarm"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_consumed_write_capacity_alarm" {
  alarm_name          = "${var.application_name}-dynamodb-write-capacity-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ConsumedWriteCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors DynamoDB consumed write capacity units"
  alarm_actions       = []

  dimensions = {
    TableName = aws_dynamodb_table.todo_table.name
  }

  tags = {
    Name        = "${var.application_name}-dynamodb-write-capacity-alarm"
    Environment = var.stack_name
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
  value = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.amplify_app.default_domain
}
