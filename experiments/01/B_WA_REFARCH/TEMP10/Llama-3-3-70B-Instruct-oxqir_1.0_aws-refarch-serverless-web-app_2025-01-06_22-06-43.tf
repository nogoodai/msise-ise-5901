# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Set up AWS provider
provider "aws" {
  region = "us-west-2"
}

# Cognito User Pool
variable "cognito_pool_name" {
  type        = string
  default     = "todo-app-user-pool"
}

variable "cognito_pool_email" {
  type        = string
  default     = "email"
}

variable "cognito_pool_email_verification" {
  type        = bool
  default     = true
}

variable "cognito_pool_password_min_length" {
  type        = number
  default     = 6
}

variable "cognito_pool_password_require_uppercase" {
  type        = bool
  default     = true
}

variable "cognito_pool_password_require_lowercase" {
  type        = bool
  default     = true
}

variable "cognito_pool_password_require_symbols_and_numbers" {
  type        = bool
  default     = false
}

resource "aws_cognito_user_pool" "todo_app" {
  name                     = var.cognito_pool_name
  email_configuration {
    email_type = "COGNITO_DEFAULT"
  }
  password_policy {
    minimum_length                   = var.cognito_pool_password_min_length
    require_uppercase                = var.cognito_pool_password_require_uppercase
    require_lowercase                = var.cognito_pool_password_require_lowercase
    require_numbers                  = var.cognito_pool_password_require_symbols_and_numbers
    require_symbols                 = var.cognito_pool_password_require_symbols_and_numbers
  }
  username_attributes = [var.cognito_pool_email]
  username_configuration {
    case_sensitivity = "Case_Insensitive"
  }
}

# Cognito User Pool Client
variable "cognito_client_name" {
  type        = string
  default     = "todo-app-client"
}

resource "aws_cognito_user_pool_client" "todo_app" {
  name                  = var.cognito_client_name
  user_pool_id          = aws_cognito_user_pool.todo_app.id
  generate_secret       = false
  allowed_oauth_flows   = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom domain for Cognito User Pool
variable "cognito_domain_prefix" {
  type        = string
  default     = "todo-app"
}

resource "aws_cognito_user_pool_domain" "todo_app" {
  domain          = "${var.cognito_domain_prefix}.auth.us-west-2.amazoncognito.com"
  user_pool_id    = aws_cognito_user_pool.todo_app.id
}

# DynamoDB Table
variable "dynamodb_table_name" {
  type        = string
  default     = "todo-table"
}

resource "aws_dynamodb_table" "todo_app" {
  name           = "${var.dynamodb_table_name}-${terraform.workspace}"
  billing_mode   = "PROVISIONED"
  read_capacity_units = 5
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
  point_in_time_recovery {
    enabled = true
  }
}

# API Gateway
variable "api_gateway_name" {
  type        = string
  default     = "todo-app-api"
}

resource "aws_api_gateway_rest_api" "todo_app" {
  name        = var.api_gateway_name
  description = "Todo app API"
}

resource "aws_api_gateway_resource" "todo_app" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  parent_id   = aws_api_gateway_rest_api.todo_app.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_app_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_authorizer" "todo_app" {
  name          = "todo-app-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app.arn]
  rest_api_id   = aws_api_gateway_rest_api.todo_app.id
}

resource "aws_api_gateway_stage" "todo_app" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.todo_app.id
  deployment_id = aws_api_gateway_deployment.todo_app.id
}

resource "aws_api_gateway_deployment" "todo_app" {
  depends_on = [aws_api_gateway_method.todo_app_post, aws_api_gateway_method.todo_app_get, aws_api_gateway_method.todo_app_put, aws_api_gateway_method.todo_app_delete]
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_app" {
  name        = "todo-app-usage-plan"
  description = "Todo app usage plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_app.id
    stage  = aws_api_gateway_stage.todo_app.stage_name
  }

  quota {
    limit  = 5000
    offset = 0
    period = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
variable "lambda_function_name" {
  type        = string
  default     = "todo-app-lambda"
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [aws_cloudwatch_log_group.todo_app.arn]
  }
  statement {
    actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.todo_app.arn]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "todo-app-lambda-policy"
  policy      = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role" "lambda_role" {
  name        = "todo-app-lambda-role"
  description = "Todo app lambda role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "todo_app" {
  filename      = "lambda_function_payload.zip"
  function_name = var.lambda_function_name
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
}

resource "aws_lambda_permission" "todo_app" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.todo_app.execution_arn}/*/*"
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "todo_app_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${aws_lambda_function.todo_app.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${aws_lambda_function.todo_app.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${aws_lambda_function.todo_app.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${aws_lambda_function.todo_app.function_name}/invocations"
}

# Amplify App
variable "amplify_app_name" {
  type        = string
  default     = "todo-app"
}

resource "aws_amplify_app" "todo_app" {
  name        = var.amplify_app_name
  description = "Todo app amplify"
  platform    = "Web"
}

resource "aws_amplify_branch" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"
  stage       = "PRODUCTION"
}

# IAM Roles and Policies
data "aws_iam_policy_document" "api_gateway_policy" {
  statement {
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [aws_cloudwatch_log_group.api_gateway.arn]
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "todo-app-api-gateway-policy"
  policy      = data.aws_iam_policy_document.api_gateway_policy.json
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "todo-app-api-gateway-role"
  description = "Todo app api gateway role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

data "aws_iam_policy_document" "amplify_policy" {
  statement {
    actions = ["amplify:CreateApp", "amplify:UpdateApp", "amplify:DeleteApp"]
    resources = [aws_amplify_app.todo_app.id]
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "todo-app-amplify-policy"
  policy      = data.aws_iam_policy_document.amplify_policy.json
}

resource "aws_iam_role" "amplify_role" {
  name        = "todo-app-amplify-role"
  description = "Todo app amplify role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "todo-app-api-gateway"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name = "todo-app-lambda"
}

resource "aws_cloudwatch_log_group" "todo_app" {
  name = "todo-app"
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_app.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_app.id
}

output "lambda_function_name" {
  value = aws_lambda_function.todo_app.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}
