provider "aws" {
  region = "us-east-1"
  version = "= 5.1.0"
}

variable "app_name" {
  default = "todo-app"
}

variable "env" {
  default = "prod"
}

variable "cognito_user_pool_name" {
  default = "todo-app-user-pool"
}

variable "cognito_user_pool_client_name" {
  default = "todo-app-client"
}

variable "dynamodb_table_name" {
  default = "todo-table-${var.env}"
}

variable "api_gateway_name" {
  default = "todo-app-api"
}

variable "api_gateway_stage_name" {
  default = "prod"
}

variable "lambda_function_name" {
  default = "todo-app-lambda"
}

variable "amplify_app_name" {
  default = "todo-app-amplify"
}

variable "github_repo" {
  default = "https://github.com/your-username/todo-app-frontend"
}

variable "github_branch" {
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app_user_pool" {
  name = var.cognito_user_pool_name
  alias_attributes = ["email"]
  auto_verified_attributes = ["email"]
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app_client" {
  name               = var.cognito_user_pool_client_name
  user_pool_id       = aws_cognito_user_pool.todo_app_user_pool.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "todo_app_domain" {
  domain       = "${var.app_name}-auth"
  user_pool_id = aws_cognito_user_pool.todo_app_user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name         = var.dynamodb_table_name
  billing_mode = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
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
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_app_api" {
  name        = var.api_gateway_name
  description = "Todo App API"
}

resource "aws_api_gateway_resource" "todo_app_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_app_api.id
  parent_id   = aws_api_gateway_rest_api.todo_app_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_app_get_item" {
  rest_api_id = aws_api_gateway_rest_api.todo_app_api.id
  resource_id = aws_api_gateway_resource.todo_app_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app_authorizer.id
}

resource "aws_api_gateway_authorizer" "todo_app_authorizer" {
  name           = "todo-app-authorizer"
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app_user_pool.arn]
  rest_api_id    = aws_api_gateway_rest_api.todo_app_api.id
}

resource "aws_api_gateway_deployment" "todo_app_deployment" {
  depends_on = [aws_api_gateway_method.todo_app_get_item]
  rest_api_id = aws_api_gateway_rest_api.todo_app_api.id
  stage_name  = var.api_gateway_stage_name
}

resource "aws_api_gateway_usage_plan" "todo_app_usage_plan" {
  name         = "todo-app-usage-plan"
  description  = "Todo App Usage Plan"
  api_key     = aws_api_gateway_api_key.todo_app_api_key.id
  product_code = " todo-app-product"
  quota_limit  = 5000
  quota_period = "DAY"
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_api_gateway_api_key" "todo_app_api_key" {
  name        = "todo-app-api-key"
  description = "Todo App API Key"
}

# Lambda Function
resource "aws_lambda_function" "todo_app_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = var.lambda_function_name
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_app_lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table_name
    }
  }
  timeout = 60
  memory_size = 1024
}

# Lambda Execution Role
resource "aws_iam_role" "todo_app_lambda_exec" {
  name        = "todo-app-lambda-exec"
  description = "Execution role for Todo App Lambda"
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

resource "aws_iam_policy" "todo_app_lambda_policy" {
  name        = "todo-app-lambda-policy"
  description = "Policy for Todo App Lambda"
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
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_app_lambda_policy_attach" {
  role       = aws_iam_role.todo_app_lambda_exec.name
  policy_arn = aws_iam_policy.todo_app_lambda_policy.arn
}

# Amplify App
resource "aws_amplify_app" "todo_app_amplify" {
  name        = var.amplify_app_name
  description = "Todo App Amplify"
}

resource "aws_amplify_branch" "todo_app_branch" {
  app_id      = aws_amplify_app.todo_app_amplify.id
  branch_name = var.github_branch
  stage        = "PRODUCTION"
  framework    = "React"
  source {
    branch      = var.github_branch
    platform    = "GitHub"
    repository = var.github_repo
  }
  auto_build {
    enabled = true
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "api-gateway-exec"
  description = "Execution role for API Gateway"
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

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "api-gateway-policy"
  description = "Policy for API Gateway"
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

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "amplify-exec"
  description = "Execution role for Amplify"
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

resource "aws_iam_policy" "amplify_policy" {
  name        = "amplify-policy"
  description = "Policy for Amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
          "amplify:CreateJob",
          "amplify:CreateWebHook",
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetDeployment",
          "amplify:GetJob",
          "amplify:GetWebHook"
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app_user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app_client.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_app_api.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.todo_app_lambda.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app_amplify.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.todo_app_branch.branch_name
}
