provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type = string
  default = "serverless-web-app"
}

variable "environment" {
  type = string
  default = "prod"
}

variable "aws_account_id" {
  type = string
}

variable "github_token" {
  type = string
  sensitive = true
}

variable "github_repo" {
  type = string
}

resource "aws_cognito_user_pool" "user_pool" {
  name                = "serverless-web-app-user-pool"
  email_verification_message = "Your verification code is {####}. "
  email_verification_subject = "Your verification code"

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  alias_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "serverless-web-app-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
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
  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "serverless-web-app-api"
  description = "Serverless web app API"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name                   = "serverless-web-app-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "item"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "put_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "delete_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_method.post_method, aws_api_gateway_method.get_method, aws_api_gateway_method.put_method, aws_api_gateway_method.delete_method]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = var.environment
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "serverless-web-app-usage-plan"
  description = "Serverless web app usage plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }
  quota {
    limit  = 5000
    offset = 2
    period  = "DAY"
  }
}

resource "aws_lambda_function" "add_item_function" {
  filename      = "functions/add-item.zip"
  function_name = "add-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "functions/get-item.zip"
  function_name = "get-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "get_all_items_function" {
  filename      = "functions/get-all-items.zip"
  function_name = "get-all-items-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "update_item_function" {
  filename      = "functions/update-item.zip"
  function_name = "update-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "complete_item_function" {
  filename      = "functions/complete-item.zip"
  function_name = "complete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "delete_item_function" {
  filename      = "functions/delete-item.zip"
  function_name = "delete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_iam_role" "lambda_role" {
  name        = "serverless-web-app-lambda-role"
  description = "Role for lambda functions"

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

resource "aws_iam_policy" "lambda_policy" {
  name        = "serverless-web-app-lambda-policy"
  description = "Policy for lambda functions"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_amplify_app" "app" {
  name        = "serverless-web-app"
  description = "Serverless web app"
  platform    = "WEB"
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = "master"
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "serverless-web-app-api-gateway-role"
  description = "Role for API Gateway"

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
  name        = "serverless-web-app-api-gateway-policy"
  description = "Policy for API Gateway"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "serverless-web-app-amplify-role"
  description = "Role for Amplify"

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
  name        = "serverless-web-app-amplify-policy"
  description = "Policy for Amplify"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
        ]
        Resource = "*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.add_item_function.arn,
    aws_lambda_function.get_item_function.arn,
    aws_lambda_function.get_all_items_function.arn,
    aws_lambda_function.update_item_function.arn,
    aws_lambda_function.complete_item_function.arn,
    aws_lambda_function.delete_item_function.arn,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}
