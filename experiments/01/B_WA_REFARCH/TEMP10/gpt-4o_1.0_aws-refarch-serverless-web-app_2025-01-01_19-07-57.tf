terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

variable "aws_region" {
  description = "The AWS region to deploy resources into"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name to be used for resource naming"
  default     = "myapp"
}

variable "project" {
  description = "The name of the project for tagging purposes"
  default     = "serverless-web-app"
}

provider "aws" {
  region = var.aws_region
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name       = "${var.stack_name}-user-pool"
    Environment = "production"
    Project    = var.project
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false

  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_scopes      = ["email", "openid", "phone"]
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name       = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project    = var.project
  }
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain      = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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
    Name       = "todo-table-${var.stack_name}"
    Environment = "production"
    Project    = var.project
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": "*",
        "Action": "execute-api:Invoke",
        "Resource": "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api.id}/*/*",
        "Condition": {
          "ForAllValues:IpAddress": {
            "aws:SourceIp": ["0.0.0.0/0"]
          }
        }
      }
    ]
  }
  EOF

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = var.project
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.api.id
  deployment_id        = aws_api_gateway_deployment.deployment.id
  description          = "Production stage for API"

  tags = {
    Name       = "${var.stack_name}-api-stage-prod"
    Environment = "production"
    Project    = var.project
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan-prod"

  api_stages {
    api_id    = aws_api_gateway_rest_api.api.id
    stage     = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name       = "${var.stack_name}-lambda-add-item"
    Environment = "production"
    Project    = var.project
  }
}

resource "aws_amplify_app" "amplify_app" {
  name              = "${var.stack_name}-amplify"
  repository        = "https://github.com/your-github-repo"

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
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  oauth_token = var.github_oauth_token

  tags = {
    Name       = "${var.stack_name}-amplify-app"
    Environment = "production"
    Project    = var.project
  }
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ],
        "Resource": "${aws_dynamodb_table.todo_table.arn}"
      },
      {
        "Effect": "Allow",
        "Action": [
          "cloudwatch:PutMetricData"
        ],
        "Resource": "*"
      }
    ]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "apigateway.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

resource "aws_iam_policy" "api_gateway_logging_policy" {
  name = "${var.stack_name}-api-gateway-logging-policy"

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "logs:CreateLogGroup",
        "Resource": "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/${aws_api_gateway_rest_api.api.id}:*"
        ]
      }
    ]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_logging_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "amplify.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

resource "aws_iam_policy" "amplify_management_policy" {
  name = "${var.stack_name}-amplify-management-policy"

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "amplify:*",
        "Resource": "*"
      }
    ]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_management_policy.arn
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

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}
