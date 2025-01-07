provider "aws" {
  region = "us-west-2"
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
  description = "The name of the stack"
}

variable "github_repo_owner" {
  type        = string
  description = "The owner of the GitHub repository"
}

variable "github_repo_name" {
  type        = string
  description = "The name of the GitHub repository"
}

variable "github_branch_name" {
  type        = string
  default     = "master"
  description = "The name of the GitHub branch"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.application_name}-${var.stack_name}-user-pool"
  email_verification_message = "Your verification code is {####}. "
  email_verification_subject = "Your verification code"
  auto_verified_attributes = ["email"]
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain               = "${var.application_name}-${var.stack_name}"
  user_pool_id       = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name                   = "${var.application_name}-${var.stack_name}-todo-table"
  billing_mode           = "PROVISIONED"
  read_capacity_units    = 5
  write_capacity_units   = 5
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
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway"
  description = "API Gateway for ${var.application_name}"
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "${var.application_name}-${var.stack_name}-cognito-authorizer"
  rest_api_id    = aws_api_gateway_rest_api.this.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_method.post, aws_api_gateway_method.get, aws_api_gateway_method.put, aws_api_gateway_method.delete]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name         = "${var.application_name}-${var.stack_name}-usage-plan"
  description  = "Usage plan for ${var.application_name}"
  api_keys     = []
  product_code = ""
  quota {
    limit  = 5000
    offset = 0
    period  = "DAY"
  }
  quota_limit {
    limit  = 100
    offset = 0
    period  = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_api_gateway_usage_plan_key" "this" {
  usage_plan_id = aws_api_gateway_usage_plan.this.id
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
}

resource "aws_api_gateway_api_key" "this" {
  name        = "${var.application_name}-${var.stack_name}-api-key"
}

# Lambda Functions
resource "aws_iam_role" "lambda" {
  name        = "${var.application_name}-${var.stack_name}-lambda-role"
  description = "Role for ${var.application_name} lambda functions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })
}

resource "aws_iam_policy" "lambda" {
  name        = "${var.application_name}-${var.stack_name}-lambda-policy"
  description = "Policy for ${var.application_name} lambda functions"

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
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Resource = "*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

resource "aws_lambda_function" "add_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.application_name}-${var.stack_name}-add-item"
  handler          = "index.add_item"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda.arn
  memory_size      = 1024
  timeout          = 60
}

resource "aws_lambda_function" "get_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.application_name}-${var.stack_name}-get-item"
  handler          = "index.get_item"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda.arn
  memory_size      = 1024
  timeout          = 60
}

resource "aws_lambda_function" "get_all_items" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.application_name}-${var.stack_name}-get-all-items"
  handler          = "index.get_all_items"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda.arn
  memory_size      = 1024
  timeout          = 60
}

resource "aws_lambda_function" "update_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.application_name}-${var.stack_name}-update-item"
  handler          = "index.update_item"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda.arn
  memory_size      = 1024
  timeout          = 60
}

resource "aws_lambda_function" "complete_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.application_name}-${var.stack_name}-complete-item"
  handler          = "index.complete_item"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda.arn
  memory_size      = 1024
  timeout          = 60
}

resource "aws_lambda_function" "delete_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.application_name}-${var.stack_name}-delete-item"
  handler          = "index.delete_item"
  runtime          = "nodejs14.x"
  role             = aws_iam_role.lambda.arn
  memory_size      = 1024
  timeout          = 60
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.application_name}-${var.stack_name}"
  description = "Amplify app for ${var.application_name}"
  app_type    = "web"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch_name
}

resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  environment_variables = {
    BUCKET_NAME = "${var.application_name}-${var.stack_name}-bucket"
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-role"
  description = "Role for ${var.application_name} API Gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })
}

resource "aws_iam_policy" "api_gateway" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-policy"
  description = "Policy for ${var.application_name} API Gateway"

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
}

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

resource "aws_iam_role" "amplify" {
  name        = "${var.application_name}-${var.stack_name}-amplify-role"
  description = "Role for ${var.application_name} Amplify"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })
}

resource "aws_iam_policy" "amplify" {
  name        = "${var.application_name}-${var.stack_name}-amplify-policy"
  description = "Policy for ${var.application_name} Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetEnvironment",
          "amplify:CreateEnvironment",
          "amplify:UpdateEnvironment",
          "amplify:DeleteEnvironment",
        ]
        Resource = aws_amplify_app.this.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "cognito_domain_endpoint" {
  value = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${aws_cognito_user_pool_domain.this.region}.amazoncognito.com"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "api_gateway_endpoint" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${aws_api_gateway_rest_api.this.region}.amazonaws.com/${aws_api_gateway_deployment.this.stage_name}/item"
}

output "iam_lambda_role_arn" {
  value = aws_iam_role.lambda.arn
}
