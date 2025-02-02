terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  default = "serverless-web-app"
}

variable "environment" {
  default = "prod"
}

variable "github_repo_owner" {
  default = "your-github-username"
}

variable "github_repo_name" {
  default = "your-github-repo-name"
}

variable "github_branch" {
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name = "${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.this.id

  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  generate_secret = false
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity_units = 5
  write_capacity_units = 5
  server_side_encryption {
    enabled = true
  }

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
      key_type = "HASH"
    },
    {
      attribute_name = "id"
      key_type = "RANGE"
    }
  ]
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id = aws_api_gateway_rest_api.this.root_resource_id
  path_part = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "POST"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "POST"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

resource "aws_api_gateway_stage" "prod" {
  stage_name = "prod"
  rest_api_id = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.get_item, aws_api_gateway_integration.post_item, aws_api_gateway_integration.put_item, aws_api_gateway_integration.delete_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name = "test"
}

resource "aws_api_gateway_usage_plan" "prod" {
  name = "prod-usage-plan"
  description = "Usage plan for ${var.stack_name} prod stage"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage_name = aws_api_gateway_stage.prod.stage_name
  }

  quota {
    limit = 5000
    offset = 0
    period = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit = 50
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename = "lambda-functions/add-item.zip"
  function_name = "${var.stack_name}-add-item"
  handler = "index.handler"
  runtime = "nodejs12.x"
  role = aws_iam_role.lambda_exec.arn
  memory_size = 1024
  timeout = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "get_item" {
  filename = "lambda-functions/get-item.zip"
  function_name = "${var.stack_name}-get-item"
  handler = "index.handler"
  runtime = "nodejs12.x"
  role = aws_iam_role.lambda_exec.arn
  memory_size = 1024
  timeout = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "update_item" {
  filename = "lambda-functions/update-item.zip"
  function_name = "${var.stack_name}-update-item"
  handler = "index.handler"
  runtime = "nodejs12.x"
  role = aws_iam_role.lambda_exec.arn
  memory_size = 1024
  timeout = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "delete_item" {
  filename = "lambda-functions/delete-item.zip"
  function_name = "${var.stack_name}-delete-item"
  handler = "index.handler"
  runtime = "nodejs12.x"
  role = aws_iam_role.lambda_exec.arn
  memory_size = 1024
  timeout = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_permission" "apigateway_add_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_get_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_update_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_delete_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name = "${var.stack_name}-app"
  description = "Amplify app for ${var.stack_name}"
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "prod" {
  app_id = aws_amplify_app.this.id
  environment_name = var.environment
}

resource "aws_amplify_backend_environment" "prod" {
  app_id = aws_amplify_app.this.id
  environment_name = var.environment
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec"
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
}

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.stack_name}-lambda-policy"
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
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "apigateway_exec" {
  name = "${var.stack_name}-apigateway-exec"
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
}

resource "aws_iam_policy" "apigateway_policy" {
  name = "${var.stack_name}-apigateway-policy"
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

resource "aws_iam_role_policy_attachment" "apigateway_policy" {
  role = aws_iam_role.apigateway_exec.name
  policy_arn = aws_iam_policy.apigateway_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name = "${var.stack_name}-amplify-exec"
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
}

resource "aws_iam_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy" {
  role = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_stage.prod.stage_name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "lambda_function_name_add_item" {
  value = aws_lambda_function.add_item.function_name
}

output "lambda_function_name_get_item" {
  value = aws_lambda_function.get_item.function_name
}

output "lambda_function_name_update_item" {
  value = aws_lambda_function.update_item.function_name
}

output "lambda_function_name_delete_item" {
  value = aws_lambda_function.delete_item.function_name
}
