provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
}

variable "github_repository" {
  type        = string
  default     = "https://github.com/user/todo-app"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app" {
  name                = "${var.stack_name}-user-pool"
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  username_attributes = ["email"]
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
  auto_verified_attributes = ["email"]
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.todo_app.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain               = "${var.stack_name}-auth"
  user_pool_id         = aws_cognito_user_pool.todo_app.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "${var.stack_name}-todo-table"
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
  server_side_encryption {
    enabled = true
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-api"
  description = "API for Todo App"
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
  name          = "${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app.arn]
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_method.todo_get, aws_api_gateway_method.todo_post, aws_api_gateway_method.todo_put, aws_api_gateway_method.todo_delete]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for Todo App"

  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
  }

  quota {
    limit  = 5000
    offset = 2
    period = "DAY"
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

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "todo_add_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_get_all_items_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_get_all_items.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_update_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_complete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_complete_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_delete_item.arn}/invocations"
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-app"
  description = "Amplify App for Todo App"
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_app_version" "todo_version" {
  app_id      = aws_amplify_app.todo_app.id
  source {
    url        = var.github_repository
    version    = var.github_branch
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "todo_lambda_exec" {
  name        = "${var.stack_name}-lambda-exec"
  description = "Execution role for Todo App Lambda"

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
  description = "Policy for Todo App Lambda"

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
      },
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
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_lambda_attach" {
  role       = aws_iam_role.todo_lambda_exec.name
  policy_arn = aws_iam_policy.todo_lambda_policy.arn
}

resource "aws_iam_role" "todo_api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec"
  description = "Execution role for Todo App API Gateway"

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
  description = "Policy for Todo App API Gateway"

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
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_api_gateway_attach" {
  role       = aws_iam_role.todo_api_gateway_exec.name
  policy_arn = aws_iam_policy.todo_api_gateway_policy.arn
}

resource "aws_iam_role" "todo_amplify_exec" {
  name        = "${var.stack_name}-amplify-exec"
  description = "Execution role for Todo App Amplify"

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
  description = "Policy for Todo App Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_amplify_attach" {
  role       = aws_iam_role.todo_amplify_exec.name
  policy_arn = aws_iam_policy.todo_amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.todo_deployment.stage_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.todo_add_item.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.todo_branch.branch_name
}
