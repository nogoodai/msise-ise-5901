# Configure the AWS Provider
provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources in."
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack to deploy."
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "todo-app-user-pool"
  alias_attributes    = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  mfa_configuration = "OPTIONAL"
  tags = {
    Name        = "todo-app-user-pool"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "todo-app-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "todo-app-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
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
  point_in_time_recovery {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "todo-api"
  description = "Todo API"
  minimum_compression_size = 0
  tags = {
    Name        = "todo-api"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "todo-app-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  rest_api_id   = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item_function.arn}/invocations"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [aws_api_gateway_integration.get_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
  stage_description = "Production stage"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name         = "todo-api-usage-plan"
  description  = "Todo API usage plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
  }
  quota {
    limit  = 5000
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
  tags = {
    Name        = "todo-api-usage-plan"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item_function" {
  filename      = "lambda_functions/add_item_function.zip"
  function_name = "todo-app-add-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "todo-app-add-item-function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "lambda_functions/get_item_function.zip"
  function_name = "todo-app-get-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "todo-app-get-item-function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "get_all_items_function" {
  filename      = "lambda_functions/get_all_items_function.zip"
  function_name = "todo-app-get-all-items-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "todo-app-get-all-items-function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "update_item_function" {
  filename      = "lambda_functions/update_item_function.zip"
  function_name = "todo-app-update-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "todo-app-update-item-function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "complete_item_function" {
  filename      = "lambda_functions/complete_item_function.zip"
  function_name = "todo-app-complete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "todo-app-complete-item-function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "delete_item_function" {
  filename      = "lambda_functions/delete_item_function.zip"
  function_name = "todo-app-delete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "todo-app-delete-item-function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "todo-app"
  description = "Todo app"
  tags = {
    Name        = "todo-app"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = "master"
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_role" {
  name        = "todo-app-lambda-role"
  description = "Lambda role for todo app"
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
  tags = {
    Name        = "todo-app-lambda-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "todo-app-lambda-policy"
  description = "Lambda policy for todo app"
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
      },
    ]
  })
  tags = {
    Name        = "todo-app-lambda-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "todo-app-api-gateway-role"
  description = "API Gateway role for todo app"
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
  tags = {
    Name        = "todo-app-api-gateway-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "todo-app-api-gateway-policy"
  description = "API Gateway policy for todo app"
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
  tags = {
    Name        = "todo-app-api-gateway-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "todo-app-amplify-role"
  description = "Amplify role for todo app"
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
  tags = {
    Name        = "todo-app-amplify-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "todo-app-amplify-policy"
  description = "Amplify policy for todo app"
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
  tags = {
    Name        = "todo-app-amplify-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_accessanalyzer_analyzer" "todo_app_analyzer" {
  analyzer_name = "todo-app-analyzer"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito user pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.user_pool_client.id
  description = "The ID of the Cognito user pool client."
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.todo_table.arn
  description = "The ARN of the DynamoDB table."
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.api.id
  description = "The ID of the API Gateway REST API."
}

output "lambda_function_arns" {
  value       = [
    aws_lambda_function.add_item_function.arn,
    aws_lambda_function.get_item_function.arn,
    aws_lambda_function.get_all_items_function.arn,
    aws_lambda_function.update_item_function.arn,
    aws_lambda_function.complete_item_function.arn,
    aws_lambda_function.delete_item_function.arn,
  ]
  description = "The ARNs of the Lambda functions."
}

output "amplify_app_id" {
  value       = aws_amplify_app.todo_app.id
  description = "The ID of the Amplify app."
}
