terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

variable "prefix" {
  type        = string
  description = "Prefix to use for resource naming"
  default     = "myapp"
}

variable "stack_name" {
  type        = string
  description = "Stack name for resource naming"
  default     = "production"
}

resource "aws_cognito_user_pool" "user_pool" {
  name                     = "${var.prefix}-user-pool-${var.stack_name}"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "${var.prefix}-user-pool"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.prefix}-user-pool-client-${var.stack_name}"
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "phone", "openid"]
  generate_secret           = false

  tags = {
    Name        = "${var.prefix}-user-pool-client"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.prefix}-${var.stack_name}"
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
    Name        = "${var.prefix}-todo-table"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.prefix}-api-${var.stack_name}"
  description = "API Gateway for ${var.prefix} application"

  tags = {
    Name        = "${var.prefix}-api"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.todo_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "${var.prefix}-cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
  identity_source        = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [aws_api_gateway_method.todo_item_method]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  variables = {
    lambdaAlias = "current"
  }

  tags = {
    Name        = "${var.prefix}-api-deployment"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  description   = "Production stage"

  variables = {
    lambdaAlias = "current"
  }

  tags = {
    Name        = "${var.prefix}-stage-prod"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_lambda_function" "item_lambda" {
  function_name = "${var.prefix}-item-handler-${var.stack_name}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.prefix}-item-lambda"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.item_lambda.function_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.prefix}-lambda-log-group"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_amplify_app" "amplify_app" {
  name              = "${var.prefix}-app-${var.stack_name}"
  repository        = "https://github.com/myuser/myrepo"
  oauth_token       = "github-oauth-token"

  build_spec = <<EOF
version: 1
applications:
  - frontend:
      phases:
        preBuild:
          commands:
            - yarn install
        build:
          commands:
            - yarn build
      artifacts:
        baseDirectory: /build
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
EOF

  basic_auth_credentials {
    username = "myuser"
    password = "mypassword"
  }
  
  auto_branch_creation_config {
    patterns       = ["master"]
    auto_build     = true
    basic_auth_credentials {
        username = "myuser"
        password = "mypassword"
    }
  }

  tags = {
    Name        = "${var.prefix}-amplify-app"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.prefix}-lambda-exec-role-${var.stack_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  tags = {
    Name        = "${var.prefix}-lambda-exec-role"
    Environment = var.stack_name
    Project     = var.prefix
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaDynamoDBExecutionRole"
}

resource "aws_iam_role_policy" "lambda_cloudwatch" {
  role = aws_iam_role.lambda_exec.id

  policy = <<EOF
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.prefix}-api-gateway-role-${var.stack_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "api_gateway_logging" {
  name = "${var.prefix}-api-gateway-logging"
  role = aws_iam_role.api_gateway_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.item_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "lambda_function_name" {
  value = aws_lambda_function.item_lambda.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
