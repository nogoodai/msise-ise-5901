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

variable "stack_name" {
  default = "my-app-stack"
}

variable "github_repo" {
  description = "GitHub repository for Amplify app"
}

resource "aws_cognito_user_pool" "user_pool" {
  name                = "user-pool-${var.stack_name}"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_CUSTOM_AUTH"]
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret     = false
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}.auth.${var.aws_region}.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "api-${var.stack_name}"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = jsonencode({
    openapi = "3.0.1"
    info = {
      title = "API"
      version = "1.0"
    }
    paths = {
      "/item" = {
        get = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.get_all_items.invoke_arn
            passthroughBehavior = "when_no_match"
            httpMethod = "POST"
            type = "aws_proxy"
          }
        }
        post = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.add_item.invoke_arn
            passthroughBehavior = "when_no_match"
            httpMethod = "POST"
            type = "aws_proxy"
          }
        }
      }
      "/item/{id}" = {
        get = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.get_item.invoke_arn
            passthroughBehavior = "when_no_match"
            httpMethod = "GET"
            type = "aws_proxy"
          }
        }
        put = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.update_item.invoke_arn
            passthroughBehavior = "when_no_match"
            httpMethod = "PUT"
            type = "aws_proxy"
          }
        }
        delete = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.delete_item.invoke_arn
            passthroughBehavior = "when_no_match"
            httpMethod = "DELETE"
            type = "aws_proxy"
          }
        }
      }
      "/item/{id}/done" = {
        post = {
          responses = {
            "200" = {
              description = "200 response"
            }
          }
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.complete_item.invoke_arn
            passthroughBehavior = "when_no_match"
            httpMethod = "POST"
            type = "aws_proxy"
          }
        }
      }
    }
  })
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
  deployment_id = aws_api_gateway_deployment.prod.id
}

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api.body))
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "usage-plan-${var.stack_name}"
  api_stages = [{
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }]

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}

resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
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

  role = aws_iam_role.lambda_exec.arn

  source_code_hash = filebase64sha256("lambda/add_item.zip")
  filename         = "lambda/add_item.zip"
}

resource "aws_lambda_function" "get_item" {
  function_name = "get-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
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

  role = aws_iam_role.lambda_exec.arn

  source_code_hash = filebase64sha256("lambda/get_item.zip")
  filename         = "lambda/get_item.zip"
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "get-all-items-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
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

  role = aws_iam_role.lambda_exec.arn

  source_code_hash = filebase64sha256("lambda/get_all_items.zip")
  filename         = "lambda/get_all_items.zip"
}

resource "aws_lambda_function" "update_item" {
  function_name = "update-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
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

  role = aws_iam_role.lambda_exec.arn

  source_code_hash = filebase64sha256("lambda/update_item.zip")
  filename         = "lambda/update_item.zip"
}

resource "aws_lambda_function" "complete_item" {
  function_name = "complete-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
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

  role = aws_iam_role.lambda_exec.arn

  source_code_hash = filebase64sha256("lambda/complete_item.zip")
  filename         = "lambda/complete_item.zip"
}

resource "aws_lambda_function" "delete_item" {
  function_name = "delete-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
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

  role = aws_iam_role.lambda_exec.arn

  source_code_hash = filebase64sha256("lambda/delete_item.zip")
  filename         = "lambda/delete_item.zip"
}

resource "aws_amplify_app" "amplify_app" {
  name = "amplify-app-${var.stack_name}"

  repository = var.github_repo

  environment_variables = {
    NODE_ENV = "production"
  }

  build_spec = <<EOF
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*

EOF

  oauth_token = var.github_oauth_token
}

resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"

  enable_auto_build = true
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action   = ["logs:*"],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_role_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_policy" "api_gateway_policy" {
  name = "api-gateway-policy-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_role_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_policy" "amplify_policy" {
  name = "amplify-policy-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
          "logs:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_role_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.prod.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_url" {
  value = aws_amplify_branch.master.web_url
}
