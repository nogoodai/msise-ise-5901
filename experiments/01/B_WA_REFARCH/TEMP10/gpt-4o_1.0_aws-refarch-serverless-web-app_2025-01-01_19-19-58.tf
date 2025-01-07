terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "application_name" {
  default = "serverless-web-app"
}

variable "stack_name" {
  default = "prod"
}

variable "github_repo" {
  default = "your-github-repo"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool"

  username_attributes = ["email"]

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
    Environment = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name            = "${var.application_name}-client"
  user_pool_id    = aws_cognito_user_pool.main.id
  generate_secret = false

  allowed_oauth_flows        = ["authorization_code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true

  tags = {
    Name        = "${var.application_name}-client"
    Environment = var.stack_name
  }
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
    Environment = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api"
  description = "API Gateway for the serverless web application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.stack_name
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  tags = {
    Name        = "${var.application_name}-stage-prod"
    Environment = var.stack_name
  }
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.application_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.application_name}-usage-plan"
    Environment = var.stack_name
  }
}

resource "aws_lambda_function" "crud_functions" {
  for_each = {
    add_item      = "POST /item"
    get_item      = "GET /item/{id}"
    get_all_items = "GET /item"
    update_item   = "PUT /item/{id}"
    complete_item = "POST /item/{id}/done"
    delete_item   = "DELETE /item/{id}"
  }

  function_name = "${var.application_name}-${each.key}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.application_name}-${each.key}"
    Environment = var.stack_name
  }
}

resource "aws_amplify_app" "main" {
  name   = var.application_name
  source_code_provider {
    github {
      owner       = "github_owner"
      repository  = var.github_repo
    }
  }

  environment_variables = {}

  enable_auto_branch_creation = true
  tags = {
    Name        = "${var.application_name}-amplify"
    Environment = var.stack_name
  }
}

resource "aws_amplify_branch" "main" {
  app_id     = aws_amplify_app.main.id
  branch_name = "master"

  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-amplify-branch"
    Environment = var.stack_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.application_name}-api-gateway-role"
    Environment = var.stack_name
  }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "${var.application_name}-api-gateway-policy"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.application_name}-amplify-role"
    Environment = var.stack_name
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.application_name}-lambda-policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}
