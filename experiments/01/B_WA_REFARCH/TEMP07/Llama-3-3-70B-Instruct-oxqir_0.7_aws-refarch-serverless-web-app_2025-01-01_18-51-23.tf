# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Create a Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "todo-app-user-pool"
  alias_attributes    = ["email"]
  email_configuration = {
    email_verifying_message = "Your verification code is {####}."
    source_arn               = "arn:aws:iam::123456789012:role/CognitoEmailRole"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

# Create a Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "todo-app-client"
  user_pool_id        = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls        = ["https://example.com/callback"]
  logout_urls          = ["https://example.com/logout"]
}

# Create a Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain       = "todo-app-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# Create a DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${aws_cognito_user_pool.user_pool.name}"
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

# Create an API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "todo-app-api"
  description = "API for Todo App"
}

# Create an API Gateway Resource
resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

# Create an API Gateway Method
resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

# Create an API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# Create an API Gateway Deployment
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_method.get_method]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

# Create an API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "todo-app-usage-plan"
  description = "Usage plan for Todo App"
  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }
  quota {
    limit  = 5000
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Create a Lambda Function
resource "aws_lambda_function" "add_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-add-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
}

# Create a Lambda Function for Get Item
resource "aws_lambda_function" "get_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-get-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
}

# Create a Lambda Function for Get All Items
resource "aws_lambda_function" "get_all_items_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-get-all-items-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
}

# Create a Lambda Function for Update Item
resource "aws_lambda_function" "update_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-update-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
}

# Create a Lambda Function for Complete Item
resource "aws_lambda_function" "complete_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-complete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
}

# Create a Lambda Function for Delete Item
resource "aws_lambda_function" "delete_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-delete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 60
}

# Create an IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name        = "todo-app-lambda-role"
  description = "Role for Todo App Lambda functions"
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

# Create an IAM Policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name        = "todo-app-lambda-policy"
  description = "Policy for Todo App Lambda functions"
  policy      = jsonencode({
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

# Attach the IAM Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Create an Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = "todo-app-amplify"
  description = "Amplify app for Todo App"
}

# Create an Amplify Branch
resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

# Create an IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name        = "todo-app-amplify-role"
  description = "Role for Todo App Amplify"
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

# Create an IAM Policy for Amplify
resource "aws_iam_policy" "amplify_policy" {
  name        = "todo-app-amplify-policy"
  description = "Policy for Todo App Amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.amplify_app.arn
      },
    ]
  })
}

# Attach the IAM Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Create an IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name        = "todo-app-api-gateway-role"
  description = "Role for Todo App API Gateway"
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

# Create an IAM Policy for API Gateway
resource "aws_iam_policy" "api_gateway_policy" {
  name        = "todo-app-api-gateway-policy"
  description = "Policy for Todo App API Gateway"
  policy      = jsonencode({
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

# Attach the IAM Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_deployment_id" {
  value = aws_api_gateway_deployment.deployment.id
}

output "lambda_function_name" {
  value = aws_lambda_function.add_item_function.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.amplify_branch.branch_name
}
