terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "my-app-stack"
}

variable "application_name" {
  type    = string
  default = "my-application"
}

locals {
  cognito_domain = "${var.application_name}-${var.stack_name}"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

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
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  user_pool_id      = aws_cognito_user_pool.main.id
  generate_secret   = false

  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain = local.cognito_domain
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"

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

  provisioned_throughput {
    read_capacity_units  = 5
    write_capacity_units = 5
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-lambda-role"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "${var.application_name}-dynamodb-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.main.arn
        Effect   = "Allow"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.main.arn
        Effect   = "Allow"
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_lambda_function" "crud_function" {
  runtime          = "nodejs12.x"
  handler          = "index.handler"
  role             = aws_iam_role.lambda_role.arn
  memory_size      = 1024
  timeout          = 60

  xray_tracing_mode = "Active"

  # Assuming the deployment package is available locally
  filename         = "path/to/your/lambda-deployment-package.zip"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  tags = {
    Name        = "${var.application_name}-crud-function"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api"
  description = "API for ${var.application_name}"

  tags = {
    Name        = "${var.application_name}-api"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "${var.application_name}-cognito-authorizer"
  identity_source        = "method.request.header.Authorization"
  provider_arns          = [aws_cognito_user_pool.main.arn]
  rest_api_id            = aws_api_gateway_rest_api.main.id
  type                   = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.item.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_method_response" "method_get_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.get_item.http_method
  status_code = "200"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.application_name}"
  retention_in_days = 14
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id

  tags = {
    Name        = "${var.application_name}-api-stage"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.application_name}-usage-plan"

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
}

resource "aws_amplify_app" "main" {
  name               = "${var.application_name}-amplify"
  repository         = "https://github.com/user/repo"
  oauth_token        = "github-token-placeholder"
  build_spec = filebase64("amplify-build-sample.yml")

  environment_variables = {
    _LIVE_UPDATES    = "1"
  }

  tags = {
    Name        = "${var.application_name}-amplify"
    Environment = "production"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "main" {
  app_id     = aws_amplify_app.main.id
  branch_name = "master"
  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.application_name}-api-gateway-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
        Effect   = "Allow"
      }
    ]
  })

  role = aws_iam_role.api_gateway_role.id
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.application_name}-amplify-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*"
        ]
        Resource = "*"
        Effect   = "Allow"
      }
    ]
  })

  role = aws_iam_role.amplify_role.id
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.main.invoke_url
}
