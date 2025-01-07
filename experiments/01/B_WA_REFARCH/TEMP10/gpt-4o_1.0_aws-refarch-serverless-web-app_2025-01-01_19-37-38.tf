terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "stack_name" {
  default = "production"
}

variable "github_repo_url" {
  description = "The GitHub repository URL for the Amplify app"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "user-pool-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "client-${var.stack_name}"

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "openid", "phone"]
  allowed_oauth_flows_user_pool_client = true

  generate_secret = false

  tags = {
    Name        = "user-pool-client-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain      = "${var.stack_name}-${var.stack_name}.auth.us-east-1.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  hash_key     = "cognito-username"
  range_key    = "id"
  billing_mode = "PROVISIONED"

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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "todo-api-${var.stack_name}"
  description = "API for serverless web application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "todo-api-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_api_gateway_resource" "items_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.items_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"

  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  request_parameters = {
    "method.request.path.id" = true
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                             = "cognito_authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.api.id
  provider_arns                    = [aws_cognito_user_pool.user_pool.arn]
  type                             = "COGNITO_USER_POOLS"

  identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_model" "error_response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  name        = "ErrorResponse"
  content_type = "application/json"
  schema      = <<EOF
{
  "type" : "object",
  "properties" : {
    "message" : { "type" : "string" }
  }
}
EOF
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  deployment_id = aws_api_gateway_deployment.deployment.id

  tags = {
    Name        = "todo-api-stage-prod-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name

  depends_on = [
    aws_api_gateway_method.get_item_method
  ]
}

resource "aws_lambda_function" "add_item_function" {
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role = aws_iam_role.lambda_execution_role.arn

  environment {
    variables = {
      STAGE = "prod"
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "add-item-lambda-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name = "/aws/lambda/${aws_lambda_function.add_item_function.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role_${var.stack_name}"

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

  tags = {
    Name        = "lambda-execution-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda_dynamodb_policy_${var.stack_name}"
  description = "Policy for lambda to access DynamoDB"
  
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:DeleteItem"
        ],
        "Resource": [
          aws_dynamodb_table.todo_table.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
  role       = aws_iam_role.lambda_execution_role.id
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_amplify_app" "amplify_app" {
  name                = "amplify-app-${var.stack_name}"
  repository          = var.github_repo_url
  oauth_token         = var.oauth_token
  build_spec          = file("buildspec.yml")

  environment_variables = {
    STAGE = "prod"
  }

  branch {
    branch_name = "master"

    enable_auto_build = true
  }

  tags = {
    Name        = "amplify-app-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify_role_${var.stack_name}"

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

  tags = {
    Name        = "amplify-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = "ServerlessWebApp"
  }
}

resource "aws_iam_policy" "amplify_resources_policy" {
  name        = "amplify_resources_policy_${var.stack_name}"
  description = "Policy for Amplify to manage resources"
  
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "amplify:CreateApp",
          "amplify:DeleteApp",
          "amplify:GetApp",
          "amplify:UpdateApp",
          "amplify:CreateBranch",
          "amplify:DeleteBranch",
          "amplify:GetBranch",
          "amplify:UpdateBranch"
        ],
        "Resource": "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_attach" {
  role       = aws_iam_role.amplify_role.id
  policy_arn = aws_iam_policy.amplify_resources_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}
