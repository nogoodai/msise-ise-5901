terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
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


resource "aws_iam_role" "api_gateway_cloudwatch_logs" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs" {
  role       = aws_iam_role.api_gateway_cloudwatch_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}


resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb" {
 name = "lambda-dynamodb-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:Query",
          "dynamodb:Scan"

        ],
        Resource = aws_dynamodb_table.main.arn,
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_apigatewayv2_api" "main" {
  name = "${var.application_name}-${var.stack_name}-api"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["*"]
  }
}


resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id                = aws_apigatewayv2_api.main.id
  authorizer_type        = "JWT"
  identity_source       = ["$context.authorizer.claims.sub"]
  name                  = "cognito-authorizer"
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.main.id]
 issuer = aws_cognito_user_pool_domain.main.cloudfront_distribution_arn
  }
}


# Placeholder for Lambda functions and API Gateway integrations - replace with actual Lambda function code and configurations
# Example for "Add Item" function:

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler" # Replace with actual handler
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_exec.arn
  # Add source code for Lambda function here (e.g., using filename or s3_bucket)
  # tracing_config {
  #   mode = "Active"
  # }
}

# Example for API Gateway integration:

# resource "aws_apigatewayv2_integration" "add_item" {
#   api_id             = aws_apigatewayv2_api.main.id
#   integration_type    = "aws_proxy"
#   integration_uri    = aws_lambda_function.add_item.invoke_arn
#   integration_method = "POST"
#   payload_format_version = "2.0"
# }

# ... similar resources for other Lambda functions and integrations


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url

 build_spec = <<-EOT
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOT
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}



output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
  value = aws_apigatewayv2_api.main.id
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}
