provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "The environment of the application"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/todo-frontend.git"
  description = "The GitHub repository for the frontend code"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch for the frontend code"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_pool" {
  name                = "${var.application_name}-user-pool"
  email_verification_subject = "Verify your email address"
  email_verification_message  = "Please click the link to verify your email address: {##VerifyEmail##}"
  alias_attributes      = ["email"]
  username_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols = false
    require_numbers = false
  }
  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_client" {
  name                                 = "${var.application_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.todo_pool.id
  generate_secret                       = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${var.application_name}.awsapp.com/callback"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "todo_domain" {
  domain       = "${var.application_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.todo_pool.id
}

# DynamoDB Table
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
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-api"
  description = "API for the Todo application"
  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name          = "${var.application_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_pool.arn]
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

resource "aws_api_gateway_integration" "todo_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_get.arn}/invocations"
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_integration.todo_get_integration]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = var.environment
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name         = "${var.application_name}-usage-plan"
  description  = "Usage plan for the Todo API"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
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
    Name        = "${var.application_name}-usage-plan"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "todo_get" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tags = {
    Name        = "${var.application_name}-get-item"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "todo_post" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tags = {
    Name        = "${var.application_name}-add-item"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "todo_put" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tags = {
    Name        = "${var.application_name}-update-item"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "todo_delete" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tags = {
    Name        = "${var.application_name}-delete-item"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "todo_done" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tags = {
    Name        = "${var.application_name}-complete-item"
    Environment = var.environment
    Project     = var.stack_name
  }
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.application_name}-app"
  description = "Amplify app for the Todo application"
  tags = {
    Name        = "${var.application_name}-app"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_deployment" "todo_deployment" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = aws_amplify_branch.todo_branch.branch_name
  environment_variables = {
    REACT_APP_API_URL = "https://${aws_api_gateway_rest_api.todo_api.id}.execute-api.${aws_api_gateway_rest_api.todo_api.region}.amazonaws.com/${aws_api_gateway_deployment.todo_deployment.stage_name}"
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "todo_lambda_role" {
  name        = "${var.application_name}-lambda-role"
  description = "IAM role for the Lambda functions"
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
  tags = {
    Name        = "${var.application_name}-lambda-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "todo_lambda_policy" {
  name        = "${var.application_name}-lambda-policy"
  description = "IAM policy for the Lambda functions"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.todo_api.region}:${aws_api_gateway_rest_api.todo_api.account_id}:log-group:/aws/lambda/${aws_lambda_function.todo_get.function_name}"
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
  tags = {
    Name        = "${var.application_name}-lambda-policy"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_lambda_attachment" {
  role       = aws_iam_role.todo_lambda_role.name
  policy_arn = aws_iam_policy.todo_lambda_policy.arn
}

resource "aws_iam_role" "todo_api_gateway_role" {
  name        = "${var.application_name}-api-gateway-role"
  description = "IAM role for the API Gateway"
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
  tags = {
    Name        = "${var.application_name}-api-gateway-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "todo_api_gateway_policy" {
  name        = "${var.application_name}-api-gateway-policy"
  description = "IAM policy for the API Gateway"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.todo_api.region}:${aws_api_gateway_rest_api.todo_api.account_id}:log-group:/aws/apigateway/${aws_api_gateway_rest_api.todo_api.id}"
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.application_name}-api-gateway-policy"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_api_gateway_attachment" {
  role       = aws_iam_role.todo_api_gateway_role.name
  policy_arn = aws_iam_policy.todo_api_gateway_policy.arn
}

resource "aws_iam_role" "todo_amplify_role" {
  name        = "${var.application_name}-amplify-role"
  description = "IAM role for the Amplify app"
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
  tags = {
    Name        = "${var.application_name}-amplify-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "todo_amplify_policy" {
  name        = "${var.application_name}-amplify-policy"
  description = "IAM policy for the Amplify app"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetJob",
          "amplify:StartJob"
        ]
        Resource = aws_amplify_app.todo_app.arn
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.application_name}-amplify-policy"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_amplify_attachment" {
  role       = aws_iam_role.todo_amplify_role.name
  policy_arn = aws_iam_policy.todo_amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_client.id
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
    aws_lambda_function.todo_get.function_name,
    aws_lambda_function.todo_post.function_name,
    aws_lambda_function.todo_put.function_name,
    aws_lambda_function.todo_delete.function_name,
    aws_lambda_function.todo_done.function_name
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.todo_branch.branch_name
}
