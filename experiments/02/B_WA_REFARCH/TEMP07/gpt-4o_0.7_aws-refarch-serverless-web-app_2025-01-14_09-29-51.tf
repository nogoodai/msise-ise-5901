terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack."
  type        = string
  default     = "my-stack"
}

variable "application_name" {
  description = "The name of the application."
  type        = string
  default     = "my-app"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = "production"
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.application_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = [
    "ALLOW_AUTH_CODE_FLOW",
    "ALLOW_IMPLICIT_FLOW"
  ]

  allowed_oauth_flows = [
    "code",
    "implicit"
  ]

  allowed_oauth_scopes = ["email", "phone", "openid"]

  generate_secret = false

  tags = {
    Name        = "${var.application_name}-client"
    Environment = "production"
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
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
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api"
  description = "API Gateway for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.application_name}-api"
    Environment = "production"
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.application_name}-api-stage"
    Environment = "production"
  }
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.application_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "crud_functions" {
  for_each = {
    "AddItem"       = "POST /item",
    "GetItem"       = "GET /item/{id}",
    "GetAllItems"   = "GET /item",
    "UpdateItem"    = "PUT /item/{id}",
    "CompleteItem"  = "POST /item/{id}/done",
    "DeleteItem"    = "DELETE /item/{id}",
  }

  filename         = "path_to_zip/${each.key}.zip"
  function_name    = "${var.application_name}-${each.key}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  memory_size      = 1024
  timeout          = 60
  tracing_config   = {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  tags = {
    Name        = "${var.application_name}-${each.key}-lambda"
    Environment = "production"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.application_name}-lambda-exec-role"

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

  tags = {
    Name        = "${var.application_name}-lambda-exec-role"
    Environment = "production"
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.application_name}-lambda-dynamodb-policy"
  description = "IAM policy for lambda to access DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.main.arn
      }
    ]
  })
}

resource "aws_iam_policy" "cloudwatch_policy" {
  name        = "${var.application_name}-cloudwatch-policy"
  description = "IAM policy for lambda to publish CloudWatch logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.cloudwatch_policy.arn
}

resource "aws_amplify_app" "main" {
  name                = "${var.application_name}-amplify-app"
  repository          = "https://github.com/your-repo/your-app"
  oauth_token         = var.github_oauth_token
  build_spec          = file("amplify-build-spec.yml")

  default_domain_association = false

  tags = {
    Name        = "${var.application_name}-amplify-app"
    Environment = "production"
  }
}

variable "github_oauth_token" {
  description = "OAuth token for GitHub integration"
  type        = string
}

resource "aws_amplify_branch" "main" {
  app_id     = aws_amplify_app.main.id
  branch_name = "master"

  environment_variables = {
    key = "value" // replace with actual key-value pairs
  }

  tags = {
    Name        = "${var.application_name}-amplify-branch"
    Environment = "production"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

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

  tags = {
    Name        = "${var.application_name}-api-gateway-role"
    Environment = "production"
  }
}

resource "aws_iam_policy" "api_gateway_logging_policy" {
  name        = "${var.application_name}-api-gateway-logging-policy"
  description = "Policy for API Gateway to write logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_logging_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_logging_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.main.execution_arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}
