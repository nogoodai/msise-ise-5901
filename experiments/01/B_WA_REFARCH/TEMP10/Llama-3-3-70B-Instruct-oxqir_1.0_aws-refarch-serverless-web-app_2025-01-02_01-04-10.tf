provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type = string
  default = "todo-app"
}

variable "env" {
  type = string
  default = "prod"
}

variable "app_name" {
  type = string
  default = "todo-app"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.app_name}-user-pool"
  email_verification_message  = "Your verification code is {####}."
  email_verification_subject  = "Your verification code"

  username_attributes = [
    "email",
  ]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name = "${var.app_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = [
    "authorization_code",
    "implicit",
  ]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = [
    "email",
    "phone",
    "openid",
  ]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.app_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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
  name        = "${var.app_name}-api"
  description = "API for todo app"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name          = "${var.app_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
  request_parameters = {
    "method.request.header.Content-Type" = true
  }
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "put_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "delete_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_method.post_method,
    aws_api_gateway_method.get_method,
    aws_api_gateway_method.put_method,
    aws_api_gateway_method.delete_method
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = var.env
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.app_name}-usage-plan"
  description = "Usage plan for todo app"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }

  quota {
    limit  = 5000
    offset = 0
    period = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item_lambda" {
  filename      = "lambda_functions/add_item_lambda.zip"
  function_name = "${var.app_name}-add-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "get_item_lambda" {
  filename      = "lambda_functions/get_item_lambda.zip"
  function_name = "${var.app_name}-get-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "update_item_lambda" {
  filename      = "lambda_functions/update_item_lambda.zip"
  function_name = "${var.app_name}-update-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_lambda_function" "delete_item_lambda" {
  filename      = "lambda_functions/delete_item_lambda.zip"
  function_name = "${var.app_name}-delete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

# API Gateway Integration
resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.add_item_lambda.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.get_item_lambda.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.put_method.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.update_item_lambda.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.delete_method.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_lambda_function.delete_item_lambda.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item_lambda.arn}/invocations"
}

# Amplify App
resource "aws_amplify_app" "app" {
  name        = var.app_name
  description = "Amplify app for todo app"
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.app.id
  branch_name = "master"
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec" {
  name        = "${var.app_name}-lambda-exec"
  description = "IAM role for lambda function execution"

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

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.app_name}-lambda-policy"
  description = "IAM policy for lambda function execution"

  policy      = jsonencode({
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
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.app_name}-api-gateway-exec"
  description = "IAM role for API Gateway execution"

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

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.app_name}-api-gateway-policy"
  description = "IAM policy for API Gateway execution"

  policy      = jsonencode({
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

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.app_name}-amplify-exec"
  description = "IAM role for Amplify execution"

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

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.app_name}-amplify-policy"
  description = "IAM policy for Amplify execution"

  policy      = jsonencode({
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
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${aws_api_gateway_rest_api.api.region}.amazonaws.com/${aws_api_gateway_deployment.deployment.stage_name}/item"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}
