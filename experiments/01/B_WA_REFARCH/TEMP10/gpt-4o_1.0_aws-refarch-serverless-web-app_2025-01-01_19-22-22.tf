terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources to."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "Unique stack name for identifying resources."
  default     = "my-stack"
}

variable "github_repository" {
  description = "GitHub repository for the Amplify app."
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito custom domain."
  default     = "myapp-" # to be replaced with actual app-specific prefix
}

resource "aws_cognito_user_pool" "app_user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name       = "${var.stack_name}-user-pool"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_client" "app_user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id

  oauth_flows = ["code", "implicit"]
  supported_identity_providers = ["COGNITO"]

  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret      = false
}

resource "aws_cognito_user_pool_domain" "app_domain" {
  domain       = "${var.cognito_domain_prefix}${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.app_user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  hash_key  = "cognito-username"
  range_key = "id"

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
    Name       = "${var.stack_name}-todo-table"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "app_api" {
  name        = "${var.stack_name}-api"
  description = "API for the serverless web application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  // Cors configuration and logging definition to follow
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name         = "${var.stack_name}-authorizer"
  rest_api_id  = aws_api_gateway_rest_api.app_api.id
  type         = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.app_user_pool.arn]
  identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_stage" "prod_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.app_api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  variables = {
    // Variables for stage-wide configurations
  }
}

resource "aws_api_gateway_method_settings" "prod_settings" {
  rest_api_id = aws_api_gateway_rest_api.app_api.id
  stage_name  = aws_api_gateway_stage.prod_stage.stage_name

  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
    data_trace_enabled = true
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs12.x"
  handler       = "add.handler"
  timeout       = 60
  memory_size   = 1024

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  // The same configuration can be repeated for other functions by changing function_name and handler
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "LambdaDynamoDBPolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = "cloudwatch:*"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "frontend_app" {
  name              = "${var.stack_name}-amplify-app"
  repository        = var.github_repository
  auto_branch_creationpatterns = ["master"]

  build_spec = jsonencode({
    version = 1
    frontend = {
      phases = {
        preBuild = {
          commands = ["npm install"]
        }
        build = {
          commands = ["npm run build"]
        }
      }
      artifacts = {
        baseDirectory = "/build"
        files = ["**/*"]
      }
      cache = {
        paths = ["node_modules/**/*"]
      }
    }
  })

  tags = {
    Name       = "${var.stack_name}-amplify-app"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "ApiGatewayCloudWatchPolicy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "AmplifyPolicy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "amplify:*"
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.app_user_pool.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "Invoke URL for the API Gateway."
  value       = aws_api_gateway_deployment.api_deployment.invoke_url
}

output "lambda_functions_arn" {
  description = "ARNs of the lambda functions."
  value       = [aws_lambda_function.add_item.arn]
  # To include all lambda functions, append them to the list
}

output "amplify_app_id" {
  description = "The ID of the AWS Amplify app."
  value       = aws_amplify_app.frontend_app.id
}
