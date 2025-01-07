provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/todo-app-frontend"
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
  email_configuration {
    email_sending_account = "DEVELOPER"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers = ["COGNITO"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain       = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.todo_app.id
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
  tags = {
    Name        = "${var.stack_name}-todo-table"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-api"
  description = "API for Todo App"
  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.stack_name}-cognito-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app.arn]
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.stack_name}-get-item-lambda/invocations"
}

resource "aws_api_gateway_deployment" "todo_api_deployment" {
  depends_on = [aws_api_gateway_integration.get_item_integration]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_api_usage_plan" {
  name         = "${var.stack_name}-api-usage-plan"
  description  = "Usage plan for Todo App API"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_api_deployment.stage_name
  }
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
resource "aws_lambda_function" "get_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-get-item-lambda"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "add_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-add-item-lambda"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "update_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-update-item-lambda"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "delete_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-delete-item-lambda"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "complete_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-complete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.stack_name}-complete-item-lambda"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = var.stack_name
  description = "Amplify App for Todo App"
  tags = {
    Name        = var.stack_name
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
  stage       = "PRODUCTION"
  enable_auto_build = true
  enable_pull_request_preview = true
  enable_performance_monitoring = true
  environment_variables = {
    REACT_APP_API_URL = "https://${aws_api_gateway_rest_api.todo_api.id}.execute-api.us-west-2.amazonaws.com/prod"
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.stack_name}-lambda-exec-role"
  description = "Execution role for Lambda functions"
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
    Name        = "${var.stack_name}-lambda-exec-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for Lambda functions"
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
  tags = {
    Name        = "${var.stack_name}-lambda-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_exec_role" {
  name        = "${var.stack_name}-api-gateway-exec-role"
  description = "Execution role for API Gateway"
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
    Name        = "${var.stack_name}-api-gateway-exec-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
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
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-api-gateway-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_exec_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_exec_role" {
  name        = "${var.stack_name}-amplify-exec-role"
  description = "Execution role for Amplify"
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
    Name        = "${var.stack_name}-amplify-exec-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
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
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-amplify-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_exec_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
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
  value = aws_api_gateway_deployment.todo_api_deployment.stage_name
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.get_item_lambda.function_name,
    aws_lambda_function.add_item_lambda.function_name,
    aws_lambda_function.update_item_lambda.function_name,
    aws_lambda_function.delete_item_lambda.function_name,
    aws_lambda_function.complete_item_lambda.function_name,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.master.branch_name
}
