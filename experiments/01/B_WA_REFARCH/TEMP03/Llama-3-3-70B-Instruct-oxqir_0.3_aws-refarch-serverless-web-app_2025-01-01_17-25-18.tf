# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "stack_name" {
  type        = string
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/your-username/your-repo-name"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain               = "${var.stack_name}-auth"
  user_pool_id         = aws_cognito_user_pool.todo_app.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-api"
  description = "Todo API"
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name           = "${var.stack_name}-authorizer"
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app.arn]
  rest_api_id    = aws_api_gateway_rest_api.todo_api.id
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_method.todo_get, aws_api_gateway_method.todo_post, aws_api_gateway_method.todo_put, aws_api_gateway_method.todo_delete]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Todo API usage plan"

  quota {
    limit  = 5000
    offset = 0
    period  = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
resource "aws_lambda_function" "todo_add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "todo_delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

# API Gateway Integration
resource "aws_api_gateway_integration" "todo_add_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.todo_add_item.region}:${aws_lambda_function.todo_add_item.account_id}:function:${aws_lambda_function.todo_add_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.todo_get_item.region}:${aws_lambda_function.todo_get_item.account_id}:function:${aws_lambda_function.todo_get_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_get_all_items_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.todo_get_all_items.region}:${aws_lambda_function.todo_get_all_items.account_id}:function:${aws_lambda_function.todo_get_all_items.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_update_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.todo_update_item.region}:${aws_lambda_function.todo_update_item.account_id}:function:${aws_lambda_function.todo_update_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_complete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.todo_complete_item.region}:${aws_lambda_function.todo_complete_item.account_id}:function:${aws_lambda_function.todo_complete_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "todo_delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_lambda_function.todo_delete_item.region}:${aws_lambda_function.todo_delete_item.account_id}:function:${aws_lambda_function.todo_delete_item.function_name}/invocations"
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-app"
  description = "Todo App"
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_backend_environment" "todo_env" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "prod"
}

# IAM Roles and Policies
resource "aws_iam_role" "todo_api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec"
  description = "API Gateway execution role"

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

resource "aws_iam_policy" "todo_api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "API Gateway policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_api_gateway_attach" {
  role       = aws_iam_role.todo_api_gateway_exec.name
  policy_arn = aws_iam_policy.todo_api_gateway_policy.arn
}

resource "aws_iam_role" "todo_lambda_exec" {
  name        = "${var.stack_name}-lambda-exec"
  description = "Lambda execution role"

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

resource "aws_iam_policy" "todo_lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Lambda policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_lambda_attach" {
  role       = aws_iam_role.todo_lambda_exec.name
  policy_arn = aws_iam_policy.todo_lambda_policy.arn
}

resource "aws_iam_role" "todo_amplify_exec" {
  name        = "${var.stack_name}-amplify-exec"
  description = "Amplify execution role"

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
}

resource "aws_iam_policy" "todo_amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Amplify policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateBackendEnvironment",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_amplify_attach" {
  role       = aws_iam_role.todo_amplify_exec.name
  policy_arn = aws_iam_policy.todo_amplify_policy.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.todo_deployment.stage_name
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.todo_add_item.function_name,
    aws_lambda_function.todo_get_item.function_name,
    aws_lambda_function.todo_get_all_items.function_name,
    aws_lambda_function.todo_update_item.function_name,
    aws_lambda_function.todo_complete_item.function_name,
    aws_lambda_function.todo_delete_item.function_name,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.todo_branch.branch_name
}
