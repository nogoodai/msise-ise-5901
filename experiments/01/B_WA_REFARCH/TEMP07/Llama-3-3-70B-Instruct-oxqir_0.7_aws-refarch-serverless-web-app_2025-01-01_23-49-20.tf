provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  default     = "todo-application"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/user/todo-app.git"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

resource "aws_cognito_user_pool" "todo_pool" {
  name                = "${var.stack_name}-user-pool"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  username_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "todo_client" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "todo_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.todo_pool.id
}

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
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-api"
  description = "Todo API"
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_integration" "todo_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_put_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_lambda.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_delete_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_lambda.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name          = "${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_pool.arn]
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_integration.todo_post_integration, aws_api_gateway_integration.todo_get_integration, aws_api_gateway_integration.todo_put_integration, aws_api_gateway_integration.todo_delete_integration]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Todo API usage plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
  }
  quota {
    limit  = 5000
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_lambda_function" "todo_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
}

resource "aws_iam_role" "todo_lambda_role" {
  name        = "${var.stack_name}-lambda-role"
  description = "Todo Lambda execution role"
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

resource "aws_iam_policy" "todo_lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Todo Lambda execution policy"
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
      {
        Action = "cloudwatch:PutMetricData"
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_lambda_policy_attachment" {
  role       = aws_iam_role.todo_lambda_role.name
  policy_arn = aws_iam_policy.todo_lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "API Gateway execution role"
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
  name        = "${var.stack_name}-api-gateway-policy"
  description = "API Gateway execution policy"
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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_amplify_app" "todo_app" {
  name        = "${var.application_name}-${var.stack_name}"
  description = "Todo App"
  build_spec = <<-EOT
    version: 0.1.0
    frontend:
      phases:
        preBuild:
          commands:
            - npm install
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: dist
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOT
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
  stage       = "PROD"
}

resource "aws_amplify_backend_environment" "todo_backend_environment" {
  app_id      = aws_amplify_app.todo_app.id
  environment = "prod"
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.stack_name}-amplify-role"
  description = "Amplify execution role"
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
  name        = "${var.stack_name}-amplify-policy"
  description = "Amplify execution policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBackendEnvironment",
          "amplify:CreateBranch",
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.todo_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.todo_api.id}.execute-api.${aws_api_gateway_rest_api.todo_api.region}.amazonaws.com/${aws_api_gateway_deployment.todo_deployment.stage_name}/item"
}

output "lambda_function_name" {
  value = aws_lambda_function.todo_lambda.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_app_url" {
  value = "https://${aws_amplify_app.todo_app.id}.amplifyapp.com"
}
