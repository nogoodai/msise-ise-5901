provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "serverless-web-app"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

variable "github_repo" {
  type        = string
  default     = "your-github-repo"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  username_attributes = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.user_pool.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain              = "${var.stack_name}"
  user_pool_id        = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "dynamodb_table" {
  name                = "todo-table-${var.stack_name}"
  billing_mode       = "PROVISIONED"
  read_capacity_units = 5
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
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.stack_name}-api-gateway"
  description = "Serverless API Gateway"
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "item"
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "put_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "delete_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.post_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.put_method.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.put_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.delete_method.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_lambda.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name          = "${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on  = [aws_api_gateway_integration.post_integration, aws_api_gateway_integration.get_integration, aws_api_gateway_integration.put_integration, aws_api_gateway_integration.delete_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name}"
}

resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
  key_type      = "API_KEY"
  key          = aws_api_gateway_api_key.api_key.id
}

resource "aws_api_gateway_api_key" "api_key" {
  name        = "${var.stack_name}-api-key"
}

# Lambda Functions
resource "aws_lambda_function" "post_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-post-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.post_lambda_role.arn
}

resource "aws_lambda_function" "get_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.get_lambda_role.arn
}

resource "aws_lambda_function" "put_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-put-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.put_lambda_role.arn
}

resource "aws_lambda_function" "delete_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.delete_lambda_role.arn
}

# IAM Roles and Policies
resource "aws_iam_role" "post_lambda_role" {
  name        = "${var.stack_name}-post-lambda-role"
  description = "Execution role for ${var.stack_name}-post-lambda"

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

resource "aws_iam_role" "get_lambda_role" {
  name        = "${var.stack_name}-get-lambda-role"
  description = "Execution role for ${var.stack_name}-get-lambda"

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

resource "aws_iam_role" "put_lambda_role" {
  name        = "${var.stack_name}-put-lambda-role"
  description = "Execution role for ${var.stack_name}-put-lambda"

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

resource "aws_iam_role" "delete_lambda_role" {
  name        = "${var.stack_name}-delete-lambda-role"
  description = "Execution role for ${var.stack_name}-delete-lambda"

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

resource "aws_iam_policy" "post_lambda_policy" {
  name        = "${var.stack_name}-post-lambda-policy"
  description = "Policy for ${var.stack_name}-post-lambda"

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
        Resource = aws_dynamodb_table.dynamodb_table.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_policy" "get_lambda_policy" {
  name        = "${var.stack_name}-get-lambda-policy"
  description = "Policy for ${var.stack_name}-get-lambda"

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
        ]
        Resource = aws_dynamodb_table.dynamodb_table.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_policy" "put_lambda_policy" {
  name        = "${var.stack_name}-put-lambda-policy"
  description = "Policy for ${var.stack_name}-put-lambda"

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
        ]
        Resource = aws_dynamodb_table.dynamodb_table.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_policy" "delete_lambda_policy" {
  name        = "${var.stack_name}-delete-lambda-policy"
  description = "Policy for ${var.stack_name}-delete-lambda"

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
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.dynamodb_table.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "post_lambda_policy_attachment" {
  role       = aws_iam_role.post_lambda_role.name
  policy_arn = aws_iam_policy.post_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "get_lambda_policy_attachment" {
  role       = aws_iam_role.get_lambda_role.name
  policy_arn = aws_iam_policy.get_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "put_lambda_policy_attachment" {
  role       = aws_iam_role.put_lambda_role.name
  policy_arn = aws_iam_policy.put_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "delete_lambda_policy_attachment" {
  role       = aws_iam_role.delete_lambda_role.name
  policy_arn = aws_iam_policy.delete_lambda_policy.arn
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = "${var.stack_name}-amplify-app"
  description = "Amplify app for ${var.stack_name}"
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_backend_environment" "amplify_backend_environment" {
  app_id      = aws_amplify_app.amplify_app.id
  environment = "prod"
}

# Output
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.dynamodb_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.deployment.stage_name
}

output "lambda_function_post_name" {
  value = aws_lambda_function.post_lambda.function_name
}

output "lambda_function_get_name" {
  value = aws_lambda_function.get_lambda.function_name
}

output "lambda_function_put_name" {
  value = aws_lambda_function.put_lambda.function_name
}

output "lambda_function_delete_name" {
  value = aws_lambda_function.delete_lambda.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.amplify_branch.branch_name
}
