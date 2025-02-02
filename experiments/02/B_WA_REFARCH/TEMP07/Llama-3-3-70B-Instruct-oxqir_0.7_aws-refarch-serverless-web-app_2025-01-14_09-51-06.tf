# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Cognito User Pool
variable "cognito_user_pool_name" {
  type        = string
  default     = "todo-app-user-pool"
  description = "The name of the Cognito User Pool"
}

variable "cognito_user_pool_domain" {
  type        = string
  default     = "todo-app"
  description = "The custom domain for the Cognito User Pool"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack"
}

resource "aws_cognito_user_pool" "this" {
  name = var.cognito_user_pool_name

  username_attributes = [
    "email",
  ]

  auto_verified_attributes = [
    "email",
  ]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols    = false
    require_numbers   = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name = "todo-app-client"

  user_pool_id = aws_cognito_user_pool.this.id

  supported_identity_providers = [
    "COGNITO",
  ]

  allowed_oauth_flows = [
    "authorization_code",
    "implicit",
  ]

  allowed_oauth_scopes = [
    "email",
    "phone",
    "openid",
  ]

  allowed_oauth_flows_user_pool_client = true
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = var.cognito_user_pool_domain
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
variable "dynamodb_table_name" {
  type        = string
  default     = "todo-table-${var.stack_name}"
  description = "The name of the DynamoDB table"
}

resource "aws_dynamodb_table" "this" {
  name         = var.dynamodb_table_name
  billing_mode = "PROVISIONED"
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
    },
  ]

  server_side_encryption {
    enabled = true
  }
}

# API Gateway
variable "api_gateway_name" {
  type        = string
  default     = "todo-app-api"
  description = "The name of the API Gateway"
}

resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_gateway_name
  description = "The REST API for the todo app"
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_authorizer" "this" {
  name          = "todo-app-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_method.post, aws_api_gateway_method.get, aws_api_gateway_method.put, aws_api_gateway_method.delete]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "todo-app-usage-plan"
  description = "The usage plan for the todo app"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_deployment.this.stage_name
  }

  quota {
    limit  = 5000
    offset = 2
    period  = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Functions
variable "lambda_function_name" {
  type        = string
  default     = "todo-app-lambda"
  description = "The name of the Lambda function"
}

resource "aws_lambda_function" "this" {
  filename      = "lambda_function_payload.zip"
  function_name = var.lambda_function_name
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }
}

resource "aws_lambda_permission" "this" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

# Amplify App
variable "amplify_app_name" {
  type        = string
  default     = "todo-app-amplify"
  description = "The name of the Amplify app"
}

resource "aws_amplify_app" "this" {
  name        = var.amplify_app_name
  description = "The Amplify app for the todo app"

  build_spec = <<-EOF
    version: 1.0
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: public
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
  EOF
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"

  stage = "PRODUCTION"
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "todo-app-api-gateway-exec"
  description = "The execution role for the API Gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "api_gateway_exec" {
  name        = "todo-app-api-gateway-exec-policy"
  description = "The execution policy for the API Gateway"

  policy      = jsonencode({
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

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "todo-app-lambda-exec"
  description = "The execution role for the Lambda function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_exec" {
  name        = "todo-app-lambda-exec-policy"
  description = "The execution policy for the Lambda function"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "todo-app-amplify-exec"
  description = "The execution role for the Amplify app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "amplify_exec" {
  name        = "todo-app-amplify-exec-policy"
  description = "The execution policy for the Amplify app"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.this.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.this.stage_name
}

output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_app_name" {
  value = aws_amplify_app.this.name
}
