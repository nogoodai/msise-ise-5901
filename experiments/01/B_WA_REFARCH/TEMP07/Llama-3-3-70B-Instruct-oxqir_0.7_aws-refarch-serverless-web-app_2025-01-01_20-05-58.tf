provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "application_name" {
  type        = string
  default     = "serverless-web-application"
}

variable "stack_name" {
  type        = string
  default     = "dev"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/repo"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.application_name}-${var.stack_name}"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  username_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.application_name}-${var.stack_name}-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls       = ["https://example.com/callback"]
  logout_urls         = ["https://example.com/logout"]
  supported_identity_providers = ["COGNITO"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.application_name}-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name           = "${var.application_name}-${var.stack_name}-authorizer"
  rest_api_id    = aws_api_gateway_rest_api.api_gateway.id
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  type          = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.application_name}-${var.stack_name}-add-item/invocations"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.post_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name         = "${var.application_name}-${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.application_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
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

# Lambda Function
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_permission" "apigateway_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = "${var.application_name}-${var.stack_name}"
  description = "Amplify app for ${var.application_name}"
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_app_version" "amplify_app_version" {
  app_id      = aws_amplify_app.amplify_app.id
  source_url  = var.github_repo
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_role" {
  name        = "${var.application_name}-${var.stack_name}-lambda-role"
  description = "IAM role for Lambda function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.application_name}-${var.stack_name}-lambda-policy"
  description = "IAM policy for Lambda function"

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

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-role"
  description = "IAM role for API Gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
  description = "IAM policy for API Gateway"

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

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.application_name}-${var.stack_name}-amplify-role"
  description = "IAM role for Amplify"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.application_name}-${var.stack_name}-amplify-policy"
  description = "IAM policy for Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:CreateBranch",
          "amplify:DeleteBranch",
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.amplify_app.arn
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

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "lambda_function_name" {
  value = aws_lambda_function.add_item.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}
