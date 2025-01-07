provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "serverless-web-app"
}

variable "project" {
  type        = string
  default     = "serverless-web-app"
}

variable "environment" {
  type        = string
  default     = "prod"
}

resource "aws_cognito_user_pool" "serverless_web_app" {
  name                = "${var.project}-${var.environment}"
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  username_attributes = ["email"]
  auto_verify                = true
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

resource "aws_cognito_user_pool_client" "serverless_web_app" {
  name                = "${var.project}-${var.environment}-client"
  user_pool_id   = aws_cognito_user_pool.serverless_web_app.id
  generate_secret = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "serverless_web_app" {
  domain       = "${var.project}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.serverless_web_app.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
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

resource "aws_api_gateway_rest_api" "serverless_web_app" {
  name        = "${var.project}-${var.environment}-api"
  description = "API for ${var.project}"
}

resource "aws_api_gateway_authorizer" "serverless_web_app" {
  name           = "${var.project}-${var.environment}-authorizer"
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.serverless_web_app.arn]
  rest_api_id   = aws_api_gateway_rest_api.serverless_web_app.id
}

resource "aws_api_gateway_resource" "serverless_web_app" {
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  parent_id   = aws_api_gateway_rest_api.serverless_web_app.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "serverless_web_app_post" {
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  resource_id = aws_api_gateway_resource.serverless_web_app.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.serverless_web_app.id
}

resource "aws_api_gateway_method" "serverless_web_app_get" {
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  resource_id = aws_api_gateway_resource.serverless_web_app.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.serverless_web_app.id
}

resource "aws_api_gateway_method" "serverless_web_app_put" {
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  resource_id = aws_api_gateway_resource.serverless_web_app.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.serverless_web_app.id
}

resource "aws_api_gateway_method" "serverless_web_app_delete" {
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  resource_id = aws_api_gateway_resource.serverless_web_app.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.serverless_web_app.id
}

resource "aws_api_gateway_integration" "serverless_web_app_post" {
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  resource_id = aws_api_gateway_resource.serverless_web_app.id
  http_method = aws_api_gateway_method.serverless_web_app_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
}

resource "aws_api_gateway_integration" "serverless_web_app_get" {
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  resource_id = aws_api_gateway_resource.serverless_web_app.id
  http_method = aws_api_gateway_method.serverless_web_app_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
}

resource "aws_api_gateway_integration" "serverless_web_app_put" {
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  resource_id = aws_api_gateway_resource.serverless_web_app.id
  http_method = aws_api_gateway_method.serverless_web_app_put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
}

resource "aws_api_gateway_integration" "serverless_web_app_delete" {
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  resource_id = aws_api_gateway_resource.serverless_web_app.id
  http_method = aws_api_gateway_method.serverless_web_app_delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
}

resource "aws_api_gateway_deployment" "serverless_web_app" {
  depends_on = [
    aws_api_gateway_integration.serverless_web_app_post,
    aws_api_gateway_integration.serverless_web_app_get,
    aws_api_gateway_integration.serverless_web_app_put,
    aws_api_gateway_integration.serverless_web_app_delete,
  ]
  rest_api_id = aws_api_gateway_rest_api.serverless_web_app.id
  stage_name  = "prod"
}

resource "aws_lambda_function" "serverless_web_app_item_post" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-${var.environment}-item-post"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.serverless_web_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "serverless_web_app_item_get" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-${var.environment}-item-get"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.serverless_web_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "serverless_web_app_item_put" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-${var.environment}-item-put"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.serverless_web_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "serverless_web_app_item_delete" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-${var.environment}-item-delete"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.serverless_web_app_lambda.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_permission" "serverless_web_app_post" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.serverless_web_app_item_post.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.serverless_web_app.execution_arn}/*/*"
}

resource "aws_lambda_permission" "serverless_web_app_get" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.serverless_web_app_item_get.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.serverless_web_app.execution_arn}/*/*"
}

resource "aws_lambda_permission" "serverless_web_app_put" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.serverless_web_app_item_put.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.serverless_web_app.execution_arn}/*/*"
}

resource "aws_lambda_permission" "serverless_web_app_delete" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.serverless_web_app_item_delete.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.serverless_web_app.execution_arn}/*/*"
}

resource "aws_iam_role" "serverless_web_app_lambda" {
  name        = "${var.project}-${var.environment}-lambda-execution-role"
  description = " Execution role for Lambda"

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

resource "aws_iam_policy" "serverless_web_app_lambda" {
  name        = "${var.project}-${var.environment}-lambda-policy"
  description = "Policy for Lambda execution"

  policy      = jsonencode({
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
      },
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

resource "aws_iam_role_policy_attachment" "serverless_web_app_lambda" {
  role       = aws_iam_role.serverless_web_app_lambda.name
  policy_arn = aws_iam_policy.serverless_web_app_lambda.arn
}

resource "aws_amplify_app" "serverless_web_app" {
  name        = "${var.project}-${var.environment}"
  description = "Amplify app for ${var.project}"
}

resource "aws_amplify_branch" "serverless_web_app" {
  app_id      = aws_amplify_app.serverless_web_app.id
  branch_name = "master"
}

resource "aws_iam_role" "serverless_web_app_api_gateway" {
  name        = "${var.project}-${var.environment}-api-gateway-execution-role"
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

resource "aws_iam_policy" "serverless_web_app_api_gateway" {
  name        = "${var.project}-${var.environment}-api-gateway-policy"
  description = "Policy for API Gateway execution"

  policy      = jsonencode({
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

resource "aws_iam_role_policy_attachment" "serverless_web_app_api_gateway" {
  role       = aws_iam_role.serverless_web_app_api_gateway.name
  policy_arn = aws_iam_policy.serverless_web_app_api_gateway.arn
}

resource "aws_iam_role" "serverless_web_app_amplify" {
  name        = "${var.project}-${var.environment}-amplify-execution-role"
  description = "Execution role for Amplify"

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
}

resource "aws_iam_policy" "serverless_web_app_amplify" {
  name        = "${var.project}-${var.environment}-amplify-policy"
  description = "Policy for Amplify execution"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:UpdateApp",
          "amplify:UpdateBranch",
          "amplify:DeleteApp",
          "amplify:DeleteBranch"
        ]
        Resource = aws_amplify_app.serverless_web_app.arn
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "serverless_web_app_amplify" {
  role       = aws_iam_role.serverless_web_app_amplify.name
  policy_arn = aws_iam_policy.serverless_web_app_amplify.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.serverless_web_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.serverless_web_app.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.serverless_web_app.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.serverless_web_app.id
}

output "api_gateway_stage" {
  value = aws_api_gateway_deployment.serverless_web_app.stage_name
}

output "lambda_function_name_post" {
  value = aws_lambda_function.serverless_web_app_item_post.function_name
}

output "lambda_function_name_get" {
  value = aws_lambda_function.serverless_web_app_item_get.function_name
}

output "lambda_function_name_put" {
  value = aws_lambda_function.serverless_web_app_item_put.function_name
}

output "lambda_function_name_delete" {
  value = aws_lambda_function.serverless_web_app_item_delete.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.serverless_web_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.serverless_web_app.branch_name
}
