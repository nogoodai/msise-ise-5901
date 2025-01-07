terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-west-2"
}

variable "stack_name" {
  description = "The stack name for resource naming."
  default     = "my-app"
}

variable "github_token" {
  description = "GitHub token for Amplify app source."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository for Amplify app source."
  type        = string
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"
  
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.stack_name}-user-pool-client"
  
  o_auth_flows = {
    authorization_code_grant = true
    implicit                 = true
  }

  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret      = false
  
  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  tags = {
    Name        = "${var.stack_name}-cognito-domain"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  hash_key       = "cognito-username"
  range_key      = "id"
  read_capacity  = 5
  write_capacity = 5

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
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_integrator" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.post_item.invoke_arn
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"

  throttling_rate_limit = 50
  throttling_burst_limit = 100

  xray_tracing_enabled = true
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name                     = "${var.stack_name}-authorizer"
  rest_api_id              = aws_api_gateway_rest_api.api.id
  identity_source          = "method.request.header.Authorization"
  type                     = "COGNITO_USER_POOLS"
  provider_arns            = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_lambda_function" "post_item" {
  function_name = "${var.stack_name}-post-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  filename      = "lambda/post_item.zip"
  memory_size   = 1024
  timeout       = 60
  
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-post-item"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-role"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_policy" "lambda_policy_dynamodb" {
  name = "${var.stack_name}-lambda-dynamodb-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = [
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ]
      Effect   = "Allow"
      Resource = aws_dynamodb_table.todo_table.arn
    }]
  })
}

resource "aws_iam_policy" "lambda_policy_cloudwatch" {
  name = "${var.stack_name}-lambda-cloudwatch-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = [
        "cloudwatch:PutMetricData"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_lambda_dynamodb" {
  role       = aws_iam_role.lambda_role.id
  policy_arn = aws_iam_policy.lambda_policy_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "attach_lambda_cloudwatch" {
  role       = aws_iam_role.lambda_role.id
  policy_arn = aws_iam_policy.lambda_policy_cloudwatch.arn
}

resource "aws_amplify_app" "frontend" {
  name = "${var.stack_name}-amplify-app"

  source_code_provider {
    github {
      owner  = "owner"
      repository = var.github_repo
      oauth_token = var.github_token
    }
  }

  build_spec = file("amplify-build-spec.yml")

  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "master"

  environment_variables = {
    NODE_ENV = "production"
  }

  tags = {
    Name        = "${var.stack_name}-amplify-branch"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.frontend.id
}
