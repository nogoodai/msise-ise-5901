provider "aws" {
  region = "us-west-2"
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "this" {
  name                     = "todo-app-user-pool"
  email_verification_message = "Your verification code is: {####}"
  email_verification_subject = "Your verification code"
  alias_attributes           = ["email"]
  auto_verified_attributes   = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "this" {
  name                                 = "todo-app-client"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  allowed_oauth_flows_client_credentials = false
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "todo-app-${aws_cognito_user_pool.this.id}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${aws_cognito_user_pool.this.id}"
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

  point_in_time_recovery {
    enabled = false
  }

  server_side_encryption {
    enabled = true
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "this" {
  name        = "todo-api"
  description = "Todo API"
}

resource "aws_api_gateway_authorizer" "this" {
  name          = "todo-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_method.post_item, aws_api_gateway_method.get_item, aws_api_gateway_method.put_item, aws_api_gateway_method.delete_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name         = "todo-usage-plan"
  description  = "Todo usage plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_deployment.this.stage_name
  }

  quota {
    limit  = 5000
    offset = 100
    period  = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda functions for CRUD operations on DynamoDB
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_functions/add_item.zip"
  function_name = "todo-add-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    DYNAMODB_TABLE = aws_dynamodb_table.this.name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_functions/get_item.zip"
  function_name = "todo-get-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    DYNAMODB_TABLE = aws_dynamodb_table.this.name
  }
}

resource "aws_lambda_function" "put_item" {
  filename      = "lambda_functions/put_item.zip"
  function_name = "todo-put-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    DYNAMODB_TABLE = aws_dynamodb_table.this.name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_functions/delete_item.zip"
  function_name = "todo-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    DYNAMODB_TABLE = aws_dynamodb_table.this.name
  }
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "this" {
  name        = "todo-app"
  description = "Todo app"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "main"
}

resource "aws_amplify_environment_variable" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  name        = "API_URL"
  value       = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${aws_api_gateway_rest_api.this.region}.amazonaws.com/${aws_api_gateway_deployment.this.stage_name}/item"
}

# IAM roles and policies
resource "aws_iam_role" "lambda_exec" {
  name        = "todo-lambda-exec"
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

resource "aws_iam_policy" "lambda_policy" {
  name        = "todo-lambda-policy"
  description = "Lambda policy"

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
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_exec" {
  name        = "todo-api-gateway-exec"
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

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "todo-api-gateway-policy"
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
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "todo-amplify-exec"
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

resource "aws_iam_policy" "amplify_policy" {
  name        = "todo-amplify-policy"
  description = "Amplify policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "api_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${aws_api_gateway_rest_api.this.region}.amazonaws.com/${aws_api_gateway_deployment.this.stage_name}/item"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.this.branch_name
}
