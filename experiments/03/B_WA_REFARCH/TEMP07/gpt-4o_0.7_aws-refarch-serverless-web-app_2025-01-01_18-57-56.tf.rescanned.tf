terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy resources in."
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack."
}

variable "application_name" {
  type        = string
  default     = "my-app"
  description = "The name of the application."
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes     = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                           = "${var.application_name}-${var.stack_name}-client"
  user_pool_id                   = aws_cognito_user_pool.user_pool.id
  allowed_oauth_flows            = ["code", "implicit"]
  allowed_oauth_scopes           = ["email", "phone", "openid"]
  generate_secret                = true
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = "production"
    Project     = var.application_name
  }

  body = <<EOF
{
  "swagger": "2.0",
  "info": {
    "title": "${var.application_name} API",
    "version": "1.0"
  },
  "paths": {
    "/item": {
      "get": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_all_items.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "post": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      }
    },
    "/item/{id}": {
      "get": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "put": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "delete": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      },
      "post": {
        "x-amazon-apigateway-integration": {
          "uri": "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item.arn}/invocations",
          "httpMethod": "POST",
          "type": "aws_proxy"
        }
      }
    }
  }
}
EOF
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "prod"

  variables = {
    "lambdaAlias" = "live"
  }

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = "$context.requestId $context.identity.sourceIp $context.identity.caller $context.identity.user $context.requestTime $context.httpMethod $context.resourcePath $context.status $context.protocol $context.responseLength $context.integrationLatency $context.integrationError $context.integrationStatus $context.authorizer"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-stage"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name = "/aws/api-gateway/${var.application_name}-${var.stack_name}"

  retention_in_days = 30

  tags = {
    Name        = "/aws/api-gateway/${var.application_name}-${var.stack_name}"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api_gateway.body))
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.application_name}-${var.stack_name}-usage-plan"

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-usage-plan"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "add_item" {
  filename         = "path/to/your/lambda.zip"
  function_name    = "${var.application_name}-add-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs14.x"
  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-add-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename         = "path/to/your/lambda.zip"
  function_name    = "${var.application_name}-get-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs14.x"
  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-get-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename         = "path/to/your/lambda.zip"
  function_name    = "${var.application_name}-get-all-items"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs14.x"
  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-get-all-items"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename         = "path/to/your/lambda.zip"
  function_name    = "${var.application_name}-update-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs14.x"
  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-update-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename         = "path/to/your/lambda.zip"
  function_name    = "${var.application_name}-complete-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs14.x"
  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-complete-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename         = "path/to/your/lambda.zip"
  function_name    = "${var.application_name}-delete-item"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs14.x"
  memory_size      = 1024
  timeout          = 60

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-delete-item"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.application_name}-${var.stack_name}-lambda-policy"
  description = "IAM policy for Lambda to interact with DynamoDB and CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-policy"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_amplify_app" "amplify_app" {
  name         = "${var.application_name}-${var.stack_name}-amplify-app"
  repository   = "https://github.com/your-repo/path"
  oauth_token  = var.github_oauth_token

  build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = "production"
    Project     = var.application_name
  }
}

variable "github_oauth_token" {
  type        = string
  description = "The GitHub OAuth token for accessing private repositories."
  sensitive   = true
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id        = aws_amplify_app.amplify_app.id
  branch_name   = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-branch"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
  description = "IAM policy for API Gateway to write CloudWatch logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "amplify.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-role"
    Environment = "production"
    Project     = var.application_name
  }
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito User Pool."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_url" {
  value       = aws_api_gateway_deployment.deployment.invoke_url
  description = "The URL for the deployed API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.amplify_app.id
  description = "The ID of the Amplify app."
}

output "lambda_function_arns" {
  value       = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn
  ]
  description = "The ARNs of the Lambda functions."
}
