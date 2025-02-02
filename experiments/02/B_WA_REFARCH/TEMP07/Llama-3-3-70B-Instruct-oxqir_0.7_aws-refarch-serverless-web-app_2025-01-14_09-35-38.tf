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

variable "github_repository" {
  default = "https://github.com/username/repository"
}

variable "github_branch" {
  default = "master"
}

variable "cognito_user_pool_name" {
  default = "serverless-web-app-user-pool"
}

variable "dynamodb_table_name" {
  default = "todo-table-${var.stack_name}"
}

variable "api_gateway_name" {
  default = "serverless-web-app-api-gateway"
}

variable "lambda_function_name" {
  default = "serverless-web-app-lambda-function"
}

variable "amplify_app_name" {
  default = "serverless-web-app-amplify-app"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = var.cognito_user_pool_name
  alias_attributes   = ["email"]
  username_attributes = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "serverless-web-app-client"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers = ["COGNITO"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}-${var.environment}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name           = var.dynamodb_table_name
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

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_gateway_name
  description = "Serverless Web App API Gateway"
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
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
  rest_api_id = aws_api_gateway_rest_api.this.id
  name        = "serverless-web-app-authorizer"
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

resource "aws_api_gateway_stage" "this" {
  stage_name    = var.environment
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_method.get, aws_api_gateway_method.post, aws_api_gateway_method.put, aws_api_gateway_method.delete]
  rest_api_id = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "serverless-web-app-usage-plan"
  description = "Serverless Web App Usage Plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }
  quota {
    limit  = 5000
    offset = 100
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Lambda Function
resource "aws_lambda_function" "this" {
  filename      = "lambda_function_payload.zip"
  function_name = var.lambda_function_name
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
}

# Lambda Function Policies
resource "aws_iam_policy" "lambda_exec" {
  name        = "serverless-web-app-lambda-exec-policy"
  description = "Serverless Web App Lambda Execution Policy"
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

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = var.amplify_app_name
  description = "Serverless Web App Amplify App"
  build_spec  = jsonencode({
    version = "1.0"
    phases = {
      install = {
        commands = [
          "npm install",
        ]
      }
      build = {
        commands = [
          "npm run build",
        ]
      }
    }
    artifacts = {
      baseDirectory = "build"
      files = [
        "**/*",
      ]
    }
  })
  custom_rules = [
    {
      source = "/<*>"
      target = "/<*>"
      status = "200"
    },
  ]
  environment_variables = {
    REACT_APP_API_URL = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${aws_api_gateway_stage.this.stage_name}.amazonaws.com/${aws_api_gateway_resource.this.path_part}"
  }
}

# Amplify Branch
resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

# IAM Roles
resource "aws_iam_role" "api_gateway_exec" {
  name        = "serverless-web-app-api-gateway-exec"
  description = "Serverless Web App API Gateway Execution Role"
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
  name        = "serverless-web-app-api-gateway-exec-policy"
  description = "Serverless Web App API Gateway Execution Policy"
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

resource "aws_iam_role" "amplify_exec" {
  name        = "serverless-web-app-amplify-exec"
  description = "Serverless Web App Amplify Execution Role"
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
  name        = "serverless-web-app-amplify-exec-policy"
  description = "Serverless Web App Amplify Execution Policy"
  policy      = jsonencode({
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

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "serverless-web-app-lambda-exec"
  description = "Serverless Web App Lambda Execution Role"
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

# Outputs
output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${aws_api_gateway_stage.this.stage_name}.amazonaws.com/${aws_api_gateway_resource.this.path_part}"
}

output "amplify_app_url" {
  value = "https://${aws_amplify_app.this.id}.amplifyapp.com"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.this.arn
}

output "lambda_function_arn" {
  value = aws_lambda_function.this.arn
}
