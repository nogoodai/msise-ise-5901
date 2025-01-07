terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "stack_name" {
  default = "my-stack"
}

variable "environment" {
  default = "production"
}

variable "github_repository" {
  default = "https://github.com/user/repo"
}

resource "aws_cognito_user_pool" "this" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

resource "aws_cognito_user_pool_client" "this" {
  user_pool_id = aws_cognito_user_pool.this.id
  name         = "${var.stack_name}-app-client"

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "openid", "phone"]
  generate_secret            = false
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}.auth.${var.region}.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_dynamodb_table" "this" {
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

  read_capacity  = 5
  write_capacity = 5

  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_stage" "this" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id

  variables = {
    authorizer_id = aws_api_gateway_authorizer.this.id
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  name = "${var.stack_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
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

resource "aws_api_gateway_authorizer" "this" {
  name              = "${var.stack_name}-authorizer"
  rest_api_id       = aws_api_gateway_rest_api.this.id
  identity_source   = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300
  type              = "COGNITO_USER_POOLS"
  provider_arns     = [aws_cognito_user_pool.this.arn]
}

resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec.arn
  source_code_hash = filebase64sha256("lambda_deployments/add_item.zip")

  filename = "lambda_deployments/add_item.zip"
}

// Similar lambda resources for Get Item, Get All Items, Update Item, Complete Item, Delete Item

resource "aws_amplify_app" "this" {
  name                = "${var.stack_name}-frontend"
  repository          = var.github_repository
  build_spec          = file("amplify_build_spec.yml")

  auto_branch_creation_config {
    enable_auto_build = true
    pattern           = "master"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exe_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_policy" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:*",
          "logs:*",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role" "apigateway_exec" {
  name = "${var.stack_name}-apigateway-exec-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "apigateway.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "apigateway_policy" {
  name = "${var.stack_name}-apigateway-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:*"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apigateway_policy_attach" {
  role       = aws_iam_role.apigateway_exec.name
  policy_arn = aws_iam_policy.apigateway_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name = "${var.stack_name}-amplify-exec-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "amplify.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "amplify:*"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.this.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
