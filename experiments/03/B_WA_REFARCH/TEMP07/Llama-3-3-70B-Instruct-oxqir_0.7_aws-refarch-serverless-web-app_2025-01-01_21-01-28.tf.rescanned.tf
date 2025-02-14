provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack"
}

variable "cognito_user_pool_name" {
  type        = string
  default     = "todo-app-user-pool"
  description = "The name of the Cognito user pool"
}

variable "cognito_user_pool_client_name" {
  type        = string
  default     = "todo-app-client"
  description = "The name of the Cognito user pool client"
}

variable "dynamodb_table_name" {
  type        = string
  default     = "todo-table-todo-app"
  description = "The name of the DynamoDB table"
}

variable "api_gateway_name" {
  type        = string
  default     = "todo-app-api"
  description = "The name of the API Gateway"
}

variable "lambda_function_name" {
  type        = string
  default     = "todo-app-lambda"
  description = "The name of the Lambda function"
}

variable "amplify_app_name" {
  type        = string
  default     = "todo-app-amplify"
  description = "The name of the Amplify app"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/todo-app-frontend.git"
  description = "The GitHub repository URL"
}

resource "aws_cognito_user_pool" "this" {
  name                     = var.cognito_user_pool_name
  email_verification_message = "Your verification code is {####}."
  email_configuration {
    source_arn = aws_iam_role.cognito_email.arn
    reply_to_email_address = "reply@example.com"
    email_sending_account  = "DEVELOPER"
  }
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  mfa_configuration = "OFF"
  tags = {
    Name        = var.cognito_user_pool_name
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name                = var.cognito_user_pool_client_name
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_dynamodb_table" "this" {
  name           = var.dynamodb_table_name
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
  point_in_time_recovery {
    enabled = true
  }
  tags = {
    Name        = var.dynamodb_table_name
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_gateway_name
  description = "Todo App API"
  tags = {
    Name        = var.api_gateway_name
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "todo-app-authorizer"
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.this.arn}/invocations"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.this.arn}/invocations"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.get_item, aws_api_gateway_integration.post_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_stage" "this" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
}

resource "aws_api_gateway_usage_plan" "this" {
  name         = "todo-app-usage-plan"
  description  = "Usage plan for todo app"
  api_keys     = []
  product_code = "todo-app-product-code"
}

resource "aws_api_gateway_usage_plan_key" "this" {
  usage_plan_id = aws_api_gateway_usage_plan.this.id
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
}

resource "aws_api_gateway_api_key" "this" {
  name        = "todo-app-api-key"
  description = "API key for todo app"
}

resource "aws_lambda_function" "this" {
  filename      = "lambda_function_payload.zip"
  function_name = var.lambda_function_name
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = var.lambda_function_name
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_amplify_app" "this" {
  name        = var.amplify_app_name
  description = "Todo App"
  tags = {
    Name        = var.amplify_app_name
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
}

resource "aws_amplify_app_version" "this" {
  app_id     = aws_amplify_app.this.id
  source_url = var.github_repo
}

resource "aws_iam_role" "cognito_email" {
  name        = "cognito-email-role"
  description = "Role for Cognito email"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "cognito-idp.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
  tags = {
    Name        = "cognito-email-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role" "lambda" {
  name        = "lambda-role"
  description = "Role for Lambda"

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
    Name        = "lambda-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role" "api_gateway" {
  name        = "api-gateway-role"
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
  tags = {
    Name        = "api-gateway-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role" "amplify" {
  name        = "amplify-role"
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
  tags = {
    Name        = "amplify-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "lambda" {
  name        = "lambda-policy"
  description = "Policy for Lambda"

  policy = jsonencode({
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
        Resource = aws_dynamodb_table.this.arn
        Effect    = "Allow"
      },
    ]
  })
  tags = {
    Name        = "lambda-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "api_gateway" {
  name        = "api-gateway-policy"
  description = "Policy for API Gateway"

  policy = jsonencode({
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
  tags = {
    Name        = "api-gateway-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "amplify" {
  name        = "amplify-policy"
  description = "Policy for Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Resource = "*"
        Effect    = "Allow"
      },
    ]
  })
  tags = {
    Name        = "amplify-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "The ID of the Cognito user pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.this.id
  description = "The ID of the Cognito user pool client"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.this.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.this.id
  description = "The ID of the API Gateway"
}

output "lambda_function_name" {
  value       = aws_lambda_function.this.function_name
  description = "The name of the Lambda function"
}

output "amplify_app_id" {
  value       = aws_amplify_app.this.id
  description = "The ID of the Amplify app"
}
