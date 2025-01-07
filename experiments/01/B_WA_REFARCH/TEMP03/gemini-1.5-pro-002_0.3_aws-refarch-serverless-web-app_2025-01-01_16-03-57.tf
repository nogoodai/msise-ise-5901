terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider aws {
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


# Cognito Resources

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
  name                               = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_useragent_only = false
  allowed_oauth_flows               = ["authorization_code", "implicit"]
  allowed_oauth_scopes              = ["email", "phone", "openid"]
  callback_urls                     = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls                       = ["http://localhost:3000/"] # Placeholder, update as needed
}

resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# DynamoDB Table

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

# IAM Roles and Policies

resource "aws_iam_role" "api_gateway_cw_logs" {
  name = "api-gateway-cw-logs-${var.stack_name}"

  assume_policy {
    statement {
      actions = ["sts:AssumeRole"]

      principals {
        type        = "Service"
        identifiers = ["apigateway.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cw_logs_attachment" {
  role       = aws_iam_role.api_gateway_cw_logs.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}


resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-${var.stack_name}"

  assume_policy {
    statement {
      actions = ["sts:AssumeRole"]
      principals {
        type        = "Service"
        identifiers = ["lambda.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_policy" "lambda_dynamodb" {
  name        = "lambda-dynamodb-${var.stack_name}"
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
          "dynamodb:Scan",
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
 "cloudwatch:PutMetricData"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_exec.id
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

# Placeholder for Lambda functions - replace with actual Lambda function code and configuration
resource "aws_lambda_function" "example" {
  # ... (Lambda function configuration)
  filename      = "lambda_function.zip" # Replace with your Lambda function zip file
  function_name = "example-lambda-${var.stack_name}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler" # Replace with your Lambda function handler
  runtime = "nodejs12.x"
  memory_size = 1024
  timeout = 60
  tracing_config {
    mode = "Active"
  }
  # ... (Other Lambda function configuration)
}


# API Gateway (Placeholder - needs integration with Lambda functions)

resource "aws_api_gateway_rest_api" "main" {
  name        = "todo-api-${var.stack_name}"
}

# Amplify (Placeholder - requires GitHub repository details)

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token
 build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /dist
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}

# Outputs

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
  value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


