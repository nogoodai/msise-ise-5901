provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

# Variables
variable "application_name" {
  type        = string
  default     = "todo-app"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
}

variable "github_repository" {
  type        = string
}

variable "github_token" {
  type        = string
  sensitive   = true
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.application_name}-user-pool"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  alias_attributes     = ["email"]
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers    = false
    require_symbols    = false
  }
  tags = {
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.application_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.application_name}.${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  key_schema = [
    {
      attribute_name = "cognito-username"
      key_type       = "HASH"
    },
    {
      attribute_name = "id"
      key_type       = "RANGE"
    }
  ]
  tags = {
    Environment = "prod"
    Project     = var.application_name
  }
  server_side_encryption {
    enabled = true
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway" {
  name        = "${var.application_name}-api-gateway"
  description = "API Gateway execution role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "api_gateway" {
  name        = "${var.application_name}-api-gateway-policy"
  description = "API Gateway execution policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

resource "aws_iam_role" "amplify" {
  name        = "${var.application_name}-amplify"
  description = "Amplify execution role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "amplify" {
  name        = "${var.application_name}-amplify-policy"
  description = "Amplify execution policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*"
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

resource "aws_iam_role" "lambda" {
  name        = "${var.application_name}-lambda"
  description = "Lambda execution role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda" {
  name        = "${var.application_name}-lambda-policy"
  description = "Lambda execution policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.this.arn
        Effect    = "Allow"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.application_name}-api"
  description = "API Gateway for ${var.application_name}"
}

resource "aws_api_gateway_authorizer" "this" {
  name        = "${var.application_name}-authorizer"
  rest_api_id = aws_api_gateway_rest_api.this.id
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.post_item.arn}/invocations"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on  = [aws_api_gateway_integration.get_item, aws_api_gateway_integration.post_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.application_name}-usage-plan"
  description = "Usage plan for ${var.application_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_deployment.this.stage_name
  }
  quota {
    limit  = 5000
    period = "DAY"
  }
  throttling {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
resource "aws_lambda_function" "get_item" {
  filename      = "lambda.zip"
  function_name = "${var.application_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "post_item" {
  filename      = "lambda.zip"
  function_name = "${var.application_name}-post-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_permission" "get_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "post_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_item.function_name
  principal     = "apigateway.amazonaws.com"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = var.application_name
  description = "Amplify app for ${var.application_name}"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
  stage       = "PRODUCTION"
}

resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  environment = "prod"
}

resource "aws_amplify_backend_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment = aws_amplify_environment.this.environment
}

# Outputs
output "api_gateway_url" {
  value = "https://${aws_api_gateway_deployment.this.rest_api_id}.execute-api.${aws_api_gateway_rest_api.this.region}.amazonaws.com/${aws_api_gateway_deployment.this.stage_name}"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.this.branch_name
}
