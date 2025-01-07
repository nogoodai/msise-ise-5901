provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

variable "github_owner" {
  type        = string
}

variable "github_repo" {
  type        = string
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                     = "${var.stack_name}-user-pool"
  email_verification_subject = "Verify your email address"
  email_verification_message = "Please click the link to verify your email address: {verificationLink}"
  sms_verification_message    = "Your verification code is {verificationCode}"
  username_attributes        = ["email"]
  alias_attributes           = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain               = "${var.stack_name}-auth"
  user_pool_id         = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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

# API Gateway REST API
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"
  binary_media_types = ["application/json"]
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
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

resource "aws_api_gateway_method" "get_items" {
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

resource "aws_api_gateway_method" "post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
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

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_items.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_items.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.put_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item_done.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.post_item_done.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_integration.post_item,
    aws_api_gateway_integration.get_item,
    aws_api_gateway_integration.get_items,
    aws_api_gateway_integration.put_item,
    aws_api_gateway_integration.post_item_done,
    aws_api_gateway_integration.delete_item
  ]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_functions/add_item.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_functions/get_item.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "get_items" {
  filename      = "lambda_functions/get_items.zip"
  function_name = "${var.stack_name}-get-items"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "put_item" {
  filename      = "lambda_functions/put_item.zip"
  function_name = "${var.stack_name}-put-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "post_item_done" {
  filename      = "lambda_functions/post_item_done.zip"
  function_name = "${var.stack_name}-post-item-done"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_functions/delete_item.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = var.stack_name
  description = "Amplify app for ${var.stack_name}"
  platform    = "WEB"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_backend_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment = "prod"
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec"
  description = "API Gateway execution role for ${var.stack_name}"
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

resource "aws_iam_policy" "api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec-policy"
  description = "Policy for API Gateway execution role for ${var.stack_name}"
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

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec"
  description = "Lambda execution role for ${var.stack_name}"
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

resource "aws_iam_policy" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec-policy"
  description = "Policy for Lambda execution role for ${var.stack_name}"
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
        Resource = aws_dynamodb_table.this.arn
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

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.stack_name}-amplify-exec"
  description = "Amplify execution role for ${var.stack_name}"
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

resource "aws_iam_policy" "amplify_exec" {
  name        = "${var.stack_name}-amplify-exec-policy"
  description = "Policy for Amplify execution role for ${var.stack_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateBackendEnvironment",
          "amplify:DeleteApp",
          "amplify:DeleteBranch",
          "amplify:DeleteBackendEnvironment"
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

resource "aws_lambda_permission" "post_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "get_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "get_items" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_items.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "put_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.put_item.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "post_item_done" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_item_done.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "delete_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_item.function_name
  principal     = "apigateway.amazonaws.com"
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${aws_api_gateway_rest_api.this.region}.amazonaws.com/prod/item"
}

output "amplify_app_url" {
  value = "https://${aws_amplify_app.this.id}.amplifyapp.com"
}
