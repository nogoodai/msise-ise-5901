terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "main"
}


provider "aws" {
  region = var.region
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_string.domain_suffix.result}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_string" "domain_suffix" {
  length  = 8
  special = false
}

resource "aws_cognito_user_pool_client" "main" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.main.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls        = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls         = ["http://localhost:3000/"] # Replace with your logout URLs
}


resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
 server_side_encryption {
    enabled = true
  }
  hash_key = "cognito-username"
  range_key = "id"
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}


resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"
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
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

data "aws_iam_policy_document" "api_gateway_account" {

 statement {
    actions = [
      "execute-api:Invoke"
    ]
    resources = [
      "*",
    ]
 principals {
      type        = "AWS"
      identifiers = [aws_iam_role.api_gateway_role.arn]
 }
  }
}
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
 policy = data.aws_iam_policy_document.api_gateway_account.json

}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
  rest_api_id     = aws_api_gateway_rest_api.main.id
 authorizer_uri = aws_lambda_function.add_item_lambda.invoke_arn
 identity_source = "method.request.header.Authorization"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"


  depends_on = [
    aws_api_gateway_integration.add_item_integration,
    aws_api_gateway_integration.get_item_integration,
    aws_api_gateway_integration.get_all_items_integration,
    aws_api_gateway_integration.update_item_integration,
    aws_api_gateway_integration.complete_item_integration,
    aws_api_gateway_integration.delete_item_integration,
  ]

}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
}


resource "aws_api_gateway_usage_plan" "main" {
 name = "${var.stack_name}-usage-plan"
 description = "Usage plan for ${var.stack_name}"

 throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

 quota_settings {
    limit  = 5000
    period = "DAY"
  }


}


resource "aws_api_gateway_usage_plan_key" "main" {
 key_id        = aws_api_gateway_api_key.main.id
 key_type      = "API_KEY"
 usage_plan_id = aws_api_gateway_usage_plan.main.id
}

resource "aws_api_gateway_api_key" "main" {
  name = "${var.stack_name}-api-key"
}


resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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



resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "${var.stack_name}-lambda-dynamodb-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
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
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
 ]
  })


}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_lambda_function" "add_item_lambda" {
  function_name = "${var.stack_name}-add-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
 tracing_config {
    mode = "Active"
 }
 # Replace with your actual code
  filename      = "add_item_lambda.zip"
  source_code_hash = filebase64sha256("add_item_lambda.zip")
}


resource "aws_lambda_function" "get_item_lambda" {
  function_name = "${var.stack_name}-get-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
 timeout       = 60
 role          = aws_iam_role.lambda_role.arn
  tracing_config {
 mode = "Active"
  }
  # Replace with your actual code
 filename      = "get_item_lambda.zip"
  source_code_hash = filebase64sha256("get_item_lambda.zip")
}


resource "aws_lambda_function" "get_all_items_lambda" {
  function_name = "${var.stack_name}-get-all-items-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
 memory_size   = 1024
  timeout       = 60
 role          = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }
 # Replace with your actual code
 filename      = "get_all_items_lambda.zip"
 source_code_hash = filebase64sha256("get_all_items_lambda.zip")
}




resource "aws_lambda_function" "update_item_lambda" {
  function_name = "${var.stack_name}-update-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
 }
  # Replace with your actual code
  filename      = "update_item_lambda.zip"
  source_code_hash = filebase64sha256("update_item_lambda.zip")
}


resource "aws_lambda_function" "complete_item_lambda" {
 function_name = "${var.stack_name}-complete-item-lambda"
 handler       = "index.handler"
 runtime       = "nodejs12.x"
  memory_size   = 1024
 timeout       = 60
  role          = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
 }
  # Replace with your actual code
  filename      = "complete_item_lambda.zip"
 source_code_hash = filebase64sha256("complete_item_lambda.zip")
}


resource "aws_lambda_function" "delete_item_lambda" {
  function_name = "${var.stack_name}-delete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
 timeout       = 60
  role          = aws_iam_role.lambda_role.arn
  tracing_config {
    mode = "Active"
  }

  # Replace with your actual code
 filename      = "delete_item_lambda.zip"
  source_code_hash = filebase64sha256("delete_item_lambda.zip")
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_resource" "item_id_resource" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 parent_id   = aws_api_gateway_resource.item_resource.id
  path_part   = "{id}"
}

resource "aws_api_gateway_method" "add_item_method" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
 http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}


resource "aws_api_gateway_integration" "add_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.add_item_method.http_method
 integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype      = "Event"
  credentials             = aws_iam_role.lambda_role.arn
  integration_method      = "POST"
  request_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200
}
EOF

  }
  integration_uri = aws_lambda_function.add_item_lambda.invoke_arn
}

resource "aws_api_gateway_method" "get_item_method" {
 rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_id_resource.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}




resource "aws_api_gateway_integration" "get_item_integration" {
 rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
 http_method             = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
 integration_subtype      = "Event"
  credentials             = aws_iam_role.lambda_role.arn
 integration_method      = "POST"
 request_templates = {
    "application/json" = <<EOF
{
 "statusCode": 200
}
EOF
  }
 integration_uri = aws_lambda_function.get_item_lambda.invoke_arn
}


resource "aws_api_gateway_method" "get_all_items_method" {
  rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_resource.id
  http_method   = "GET"
 authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}



resource "aws_api_gateway_integration" "get_all_items_integration" {
 rest_api_id             = aws_api_gateway_rest_api.main.id
 resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.get_all_items_method.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype      = "Event"
  credentials             = aws_iam_role.lambda_role.arn
  integration_method      = "POST"
 request_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200
}
EOF
  }
  integration_uri = aws_lambda_function.get_all_items_lambda.invoke_arn
}





resource "aws_api_gateway_method" "update_item_method" {
 rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_id_resource.id
 http_method   = "PUT"
 authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}




resource "aws_api_gateway_integration" "update_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
 http_method             = aws_api_gateway_method.update_item_method.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
 integration_subtype      = "Event"
  credentials             = aws_iam_role.lambda_role.arn
  integration_method      = "POST"
  request_templates = {
 "application/json" = <<EOF
{
 "statusCode": 200
}
EOF
 }
  integration_uri = aws_lambda_function.update_item_lambda.invoke_arn
}



resource "aws_api_gateway_method" "complete_item_method" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_id_resource.id
  http_method   = "POST"
 authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}



resource "aws_api_gateway_integration" "complete_item_integration" {
 rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
  http_method             = aws_api_gateway_method.complete_item_method.http_method
 integration_http_method = "POST"
  type                    = "aws_proxy"
 integration_subtype      = "Event"
  credentials             = aws_iam_role.lambda_role.arn
  integration_method      = "POST"
  request_templates = {
    "application/json" = <<EOF
{
 "statusCode": 200
}
EOF

  }
  integration_uri = aws_lambda_function.complete_item_lambda.invoke_arn
}




resource "aws_api_gateway_method" "delete_item_method" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_id_resource.id
 http_method   = "DELETE"
 authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}


resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
 resource_id             = aws_api_gateway_resource.item_id_resource.id
 http_method             = aws_api_gateway_method.delete_item_method.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
 integration_subtype      = "Event"
 credentials             = aws_iam_role.lambda_role.arn
  integration_method      = "POST"
  request_templates = {
    "application/json" = <<EOF
{
  "statusCode": 200
}
EOF

 }
  integration_uri = aws_lambda_function.delete_item_lambda.invoke_arn
}



resource "aws_amplify_app" "main" {
  name       = var.stack_name
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub personal access token
 build_spec = <<YAML
version: 0.1
frontend:
  phases:
    preBuild:
 npm install
    build:
      commands:
        - npm run-script build
  artifacts:
    baseDirectory: /
    files:
 - '**/*'
  cache:
    paths:
      - node_modules/**/*
YAML
}


resource "aws_amplify_branch" "master" {
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

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.todo_table.name
}


output "api_gateway_url" {
 value = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}
