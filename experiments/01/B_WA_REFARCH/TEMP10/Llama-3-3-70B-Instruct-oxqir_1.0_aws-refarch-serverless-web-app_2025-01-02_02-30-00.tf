provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

variable "stack_name" {
  default = "my-stack"
}
variable "github_repo" {
  default = "my-github-repo"
}
variable "github_branch" {
  default = "main"
}

# Cognito User Pool and Client
resource "aws_cognito_user_pool" "pool" {
  name                     = "${var.stack_name}-user-pool"
  email_configuration      = {
    email_verifying = true
  }
  email_verification_message = "Please click this link to verify your email address: {##Verify Email##}"
  username_configuration = {
    case_sensitive = false
  }
  password_policy = {
    minimum_length                   = 6
    require_uppercase               = true
    require_lowercase               = true
    require_numbers                 = false
    require_symbols                 = false
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                          = "${var.stack_name}-user-pool-client"
  user_pool_id                  = aws_cognito_user_pool.pool.id
  generate_secret              = false
  allowed_oauth_flows          = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool = true
  allowed_oauth_scopes          = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
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
  server_side_encryption {
    enabled = true
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name} stack"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.auth.id
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.auth.id
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.auth.id
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.auth.id
}

resource "aws_api_gateway_method" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.auth.id
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_all_items_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_all_items.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_all_items.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "auth" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  name        = "${var.stack_name}-authorizer"
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.pool.arn]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.post_item_integration,
    aws_api_gateway_integration.get_item_integration,
    aws_api_gateway_integration.put_item_integration,
    aws_api_gateway_integration.delete_item_integration,
    aws_api_gateway_integration.get_all_items_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "plan" {
  name        = "${var.stack_name}-plan"
  description = "Usage plan for ${var.stack_name} API"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }
  quota {
    limit  = 5000
    offset = 2
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.stack_name}-add-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "get_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.stack_name}-get-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "update_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.stack_name}-update-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "delete_item" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.stack_name}-delete-item"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "get_all_items" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.stack_name}-get-all-items"
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  role             = aws_iam_role.lambda_exec.arn
}

# Amplify App
resource "aws_amplify_app" "app" {
  name        = "${var.stack_name}"
  description = "Amplify app for ${var.stack_name} stack"
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = "main"
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec"
  description = "Execution role for API Gateway"

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

resource "aws_iam_policy" "api_gateway_logging" {
  name        = "${var.stack_name}-api-gateway-logging"
  description = "Policy for API Gateway logging"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_logging" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_logging.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec"
  description = "Execution role for Lambda"

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

resource "aws_iam_policy" "lambda_dynamodb" {
  name        = "${var.stack_name}-lambda-dynamodb"
  description = "Policy for Lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

resource "aws_iam_policy" "lambda_cloudwatch" {
  name        = "${var.stack_name}-lambda-cloudwatch"
  description = "Policy for Lambda to publish metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_cloudwatch.arn
}
