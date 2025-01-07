# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Define variables
variable "stack_name" {
  type = string
}

variable "github_token" {
  type = string
  sensitive = true
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type = string
  default = "master"
}

variable "aws_region" {
  type = string
  default = "us-west-2"
}

variable "aws_account_id" {
  type = string
}

provider "aws" {
  region = var.aws_region
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"
  alias_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers = false
    require_symbols = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id
  generate_secret = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls = ["https://${var.stack_name}.auth.${var.aws_region}.amazoncognito.com/oauth2/idpresponse"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "main" {
  domain = "${var.stack_name}.auth.${var.aws_region}.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB table
resource "aws_dynamodb_table" "main" {
  name = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity_units = 5
  write_capacity_units = 5
  hash_key = "cognito-username"
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
resource "aws_api_gateway_rest_api" "main" {
  name = "${var.stack_name}-rest-api"
  description = "REST API for ${var.stack_name}"
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id = aws_api_gateway_rest_api.main.root_resource_id
  path_part = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "GET"
  integration_http_method = "POST"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  integration_http_method = "POST"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_deployment" "main" {
  depends_on = [aws_api_gateway_integration.get_item, aws_api_gateway_integration.post_item]
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name = "prod"
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage = aws_api_gateway_deployment.main.stage_name
  }
  quota {
    limit = 5000
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit = 50
  }
}

resource "aws_api_gateway_authorizer" "main" {
  name = "${var.stack_name}-authorizer"
  rest_api_id = aws_api_gateway_rest_api.main.id
  type = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# Lambda functions
resource "aws_lambda_function" "add_item" {
  filename = "lambda-function-code.zip"
  function_name = "${var.stack_name}-add-item-lambda"
  handler = "index.handler"
  runtime = "nodejs12.x"
  role = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = "todo-table-${var.stack_name}"
    }
  }
}

resource "aws_lambda_function" "get_item" {
  filename = "lambda-function-code.zip"
  function_name = "${var.stack_name}-get-item-lambda"
  handler = "index.handler"
  runtime = "nodejs12.x"
  role = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = "todo-table-${var.stack_name}"
    }
  }
}

resource "aws_lambda_permission" "add_item" {
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_item" {
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# Amplify app
resource "aws_amplify_app" "main" {
  name = "${var.stack_name}-amplify-app"
  description = "Amplify app for ${var.stack_name}"
  platform = "WEB"
}

resource "aws_amplify_branch" "main" {
  app_id = aws_amplify_app.main.id
  branch_name = var.github_branch
  stage = "PRODUCTION"
  environment_variables = {
    DYNAMODB_TABLE = "todo-table-${var.stack_name}"
  }
}

resource "aws_amplify_webhook" "main" {
  app_id = aws_amplify_app.main.id
  branch_name = aws_amplify_branch.main.branch_name
  description = "Webhook for ${var.stack_name}"
}

# IAM roles and policies
resource "aws_iam_policy" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec-policy"
  description = "Policy for Lambda execution"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/todo-table-${var.stack_name}"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec-role"
  description = "Role for Lambda execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_policy" "amplify_exec" {
  name = "${var.stack_name}-amplify-exec-policy"
  description = "Policy for Amplify execution"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
          "amplify:CreateWebhook"
        ]
        Resource = "arn:aws:amplify:${var.aws_region}:${var.aws_account_id}:apps/${aws_amplify_app.main.id}"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_exec" {
  name = "${var.stack_name}-amplify-exec-role"
  description = "Role for Amplify execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = "todo-table-${var.stack_name}"
}

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.main.branch_name
}
