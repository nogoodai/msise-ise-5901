provider "aws" {
  region  = "us-west-2"
  version = "5.1.0"
}

variable "application_name" {
  default = "todo-app"
}

variable "environment" {
  default = "prod"
}

variable "github_repo" {
  default = "https://github.com/user/todo-app.git"
}

variable "github_branch" {
  default = "master"
}

variable "cognito_pool_name" {
  default = "todo-pool"
}

variable "dynamodb_table_name" {
  default = "todo-table-${var.application_name}"
}

variable "api_gateway_name" {
  default = "todo-api"
}

variable "lambda_function_name" {
  default = "todo-lambda"
}

variable "amplify_app_name" {
  default = "todo-amplify"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = var.cognito_pool_name
  alias_attributes   = ["email"]
  username_attributes = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }
  Tags = {
    Name        = var.cognito_pool_name
    Environment = var.environment
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = var.cognito_pool_name
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls = ["https://example.com/callback"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.application_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name         = var.dynamodb_table_name
  billing_mode = "PROVISIONED"
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
  table_status = "ACTIVE"
  server_side_encryption {
    enabled = true
  }
  Tags = {
    Name        = var.dynamodb_table_name
    Environment = var.environment
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_gateway_name
  description = "Todo App API"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_authorizer" "this" {
  name        = "CognitoAuthorizer"
  rest_api_id = aws_api_gateway_rest_api.this.id
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  request_templates = {
    "application/json" = "{\"action\": \"CreateItem\"}"
  }
}

resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.this.arn}/invocations"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.post]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# Lambda Function
resource "aws_lambda_function" "this" {
  filename      = "lambda_function_payload.zip"
  function_name = var.lambda_function_name
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_permission" "this" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = var.amplify_app_name
  description = "Todo App"
  platform   = "WEB"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
  framework   = "React"
  stage       = "PRODUCTION"
}

resource "aws_amplify_app_version" "this" {
  app_id      = aws_amplify_app.this.id
  source_url  = var.github_repo
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway" {
  name        = "ApiGatewayRole"
  description = "Role for API Gateway"
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
}

resource "aws_iam_policy" "api_gateway" {
  name        = "ApiGatewayPolicy"
  description = "Policy for API Gateway"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "logs:CreateLogGroup"
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = "logs:CreateLogStream"
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = "logs:PutLogEvents"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

resource "aws_iam_role" "lambda" {
  name        = "LambdaRole"
  description = "Role for Lambda"
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

resource "aws_iam_policy" "lambda" {
  name        = "LambdaPolicy"
  description = "Policy for Lambda"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "dynamodb:GetItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = "dynamodb:PutItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = "dynamodb:UpdateItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = "dynamodb:DeleteItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = "cloudwatch:PublishMetric"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
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

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
