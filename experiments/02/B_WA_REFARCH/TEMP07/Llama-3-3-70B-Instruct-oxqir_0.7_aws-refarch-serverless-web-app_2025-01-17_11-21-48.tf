terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type = string
  default = "todo-app"
}

variable "environment" {
  type = string
  default = "prod"
}

variable "github_repository" {
  type = string
  default = "https://github.com/user/todo-app"
}

variable "github_branch" {
  type = string
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_app" {
  name                = "${var.stack_name}-user-pool"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = var.environment
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_app" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.todo_app.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers = ["COGNITO"]
  callback_urls = ["https://${aws_api_gateway_domain_name.todo_app.domain_name}"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_app" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.todo_app.id
}

# DynamoDB table
resource "aws_dynamodb_table" "todo_table" {
  name         = "${var.stack_name}-todo-table"
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
  tags = {
    Name        = "${var.stack_name}-todo-table"
    Environment = var.environment
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_app" {
  name        = "${var.stack_name}-api"
  description = "${var.stack_name} API"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "todo_app" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  parent_id   = aws_api_gateway_rest_api.todo_app.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_app_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_method" "todo_app_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_app.id
}

resource "aws_api_gateway_authorizer" "todo_app" {
  name          = "${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app.arn]
  rest_api_id   = aws_api_gateway_rest_api.todo_app.id
}

resource "aws_api_gateway_deployment" "todo_app" {
  depends_on = [aws_api_gateway_method.todo_app_get, aws_api_gateway_method.todo_app_post, aws_api_gateway_method.todo_app_put, aws_api_gateway_method.todo_app_delete]
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  stage_name  = var.environment
}

resource "aws_api_gateway_domain_name" "todo_app" {
  domain_name     = "${var.stack_name}-api"
  certificate_arn = aws_acm_certificate.todo_app.arn
}

resource "aws_acm_certificate" "todo_app" {
  domain_name       = "${var.stack_name}-api"
  validation_method = "DNS"
}

resource "aws_route53_record" "todo_app" {
  name    = "${var.stack_name}-api"
  type    = "A"
  zone_id = aws_route53_zone.todo_app.id
  alias {
    name                   = aws_api_gateway_domain_name.todo_app.cloudfront_domain_name
    zone_id               = aws_api_gateway_domain_name.todo_app.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "todo_app" {
  name = "${var.stack_name}-api"
}

# Lambda functions
resource "aws_lambda_function" "todo_app_get" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.todo_app_lambda.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  depends_on = [aws_iam_role_policy_attachment.todo_app_lambda]
}

resource "aws_lambda_function" "todo_app_post" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.todo_app_lambda.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  depends_on = [aws_iam_role_policy_attachment.todo_app_lambda]
}

resource "aws_lambda_function" "todo_app_put" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.todo_app_lambda.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  depends_on = [aws_iam_role_policy_attachment.todo_app_lambda]
}

resource "aws_lambda_function" "todo_app_delete" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.todo_app_lambda.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  depends_on = [aws_iam_role_policy_attachment.todo_app_lambda]
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "todo_app_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_get.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_get.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_post.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_put.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_put.arn}/invocations"
}

resource "aws_api_gateway_integration" "todo_app_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_app.id
  resource_id = aws_api_gateway_resource.todo_app.id
  http_method = aws_api_gateway_method.todo_app_delete.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_app.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_app_delete.arn}/invocations"
}

# Amplify app
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-app"
  description = "${var.stack_name} app"
}

resource "aws_amplify_branch" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "todo_app" {
  app_id      = aws_amplify_app.todo_app.id
  environment = var.environment
}

# IAM roles and policies
resource "aws_iam_role" "todo_app_api_gateway" {
  name        = "${var.stack_name}-api-gateway"
  description = "${var.stack_name} API Gateway role"
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

resource "aws_iam_role_policy" "todo_app_api_gateway" {
  name   = "${var.stack_name}-api-gateway-policy"
  role   = aws_iam_role.todo_app_api_gateway.id
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
      }
    ]
  })
}

resource "aws_iam_role" "todo_app_amplify" {
  name        = "${var.stack_name}-amplify"
  description = "${var.stack_name} Amplify role"
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

resource "aws_iam_role_policy" "todo_app_amplify" {
  name   = "${var.stack_name}-amplify-policy"
  role   = aws_iam_role.todo_app_amplify.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetEnvironment",
        ]
        Resource = aws_amplify_app.todo_app.arn
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "todo_app_lambda" {
  name        = "${var.stack_name}-lambda"
  description = "${var.stack_name} Lambda role"
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

resource "aws_iam_role_policy" "todo_app_lambda" {
  name   = "${var.stack_name}-lambda-policy"
  role   = aws_iam_role.todo_app_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

# Outputs
output "api_gateway_url" {
  value = "https://${aws_api_gateway_domain_name.todo_app.domain_name}/${aws_api_gateway_deployment.todo_app.stage_name}"
}

output "amplify_app_url" {
  value = "https://${aws_amplify_app.todo_app.id}.amplifyapp.com"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app.id
}
