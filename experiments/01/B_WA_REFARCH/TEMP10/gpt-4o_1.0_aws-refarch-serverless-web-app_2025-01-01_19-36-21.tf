terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-west-2"
}

variable "application_name" {
  default = "todo-app"
}

variable "stack_name" {
  default = "production-stack"
}

resource "aws_cognito_user_pool" "user_pool" {
  name                       = "${var.application_name}-user-pool"
  auto_verified_attributes   = ["email"]
  username_attributes        = ["email"]
  
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id   = aws_cognito_user_pool.user_pool.id
  name           = "${var.application_name}-client"
  generate_secret = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.stack_name}"
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

  provisioned_throughput {
    read_capacity_units  = 5
    write_capacity_units = 5
  }

  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api"
  description = "API for ${var.application_name}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  body = jsonencode({
    "swagger": "2.0",
    "info": {
      "title":      "${var.application_name} API",
      "version":    "1.0"
    },
    "paths": {
      "/item": {
        "post": {
          "summary": "Add Item",
          "x-amazon-apigateway-integration": {
            "httpMethod": "POST",
            "type": "AWS_PROXY",
            "uri": "${aws_lambda_function.add_item.invoke_arn}",
            "passthroughBehavior": "WHEN_NO_MATCH"
          }
        },
        "get": {
          "summary": "Get All Items",
          "x-amazon-apigateway-integration": {
            "httpMethod": "GET",
            "type": "AWS_PROXY",
            "uri": "${aws_lambda_function.get_all_items.invoke_arn}",
            "passthroughBehavior": "WHEN_NO_MATCH"
          }
        }
      },
      "/item/{id}": {
        "get": {
          "summary": "Get Item",
          "parameters": [{"name": "id", "in": "path", "required": true, "type": "string"}],
          "x-amazon-apigateway-integration": {
            "httpMethod": "GET",
            "type": "AWS_PROXY",
            "uri": "${aws_lambda_function.get_item.invoke_arn}",
            "passthroughBehavior": "WHEN_NO_MATCH"
          }
        },
        "put": {
          "summary": "Update Item",
          "parameters": [{"name": "id", "in": "path", "required": true, "type": "string"}],
          "x-amazon-apigateway-integration": {
            "httpMethod": "PUT",
            "type": "AWS_PROXY",
            "uri": "${aws_lambda_function.update_item.invoke_arn}",
            "passthroughBehavior": "WHEN_NO_MATCH"
          }
        },
        "post": {
          "summary": "Complete Item",
          "parameters": [{"name": "id", "in": "path", "required": true, "type": "string"}],
          "x-amazon-apigateway-integration": {
            "httpMethod": "POST",
            "type": "AWS_PROXY",
            "uri": "${aws_lambda_function.complete_item.invoke_arn}",
            "passthroughBehavior": "WHEN_NO_MATCH"
          }
        },
        "delete": {
          "summary": "Delete Item",
          "parameters": [{"name": "id", "in": "path", "required": true, "type": "string"}],
          "x-amazon-apigateway-integration": {
            "httpMethod": "DELETE",
            "type": "AWS_PROXY",
            "uri": "${aws_lambda_function.delete_item.invoke_arn}",
            "passthroughBehavior": "WHEN_NO_MATCH"
          }
        }
      }
    }
  })
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deploy.id

  xray_tracing_enabled = true
}

resource "aws_api_gateway_deployment" "api_deploy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api.body))
  }
}

resource "aws_api_gateway_method_settings" "settings" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name

  method_path = "/*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
    data_trace_enabled = true
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.application_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
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

resource "aws_lambda_function" "add_item" {
  function_name = "${var.application_name}-add-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn

  # Assuming the ZIP file with code is provided
  filename         = "/path/to/add_item.zip"
  source_code_hash = filemd5("/path/to/add_item.zip")
}

resource "aws_lambda_function" "get_item" {
  function_name = "${var.application_name}-get-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn

  filename         = "/path/to/get_item.zip"
  source_code_hash = filemd5("/path/to/get_item.zip")
}

resource "aws_lambda_function" "get_all_items" {
  function_name = "${var.application_name}-get-all-items"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn

  filename         = "/path/to/get_all_items.zip"
  source_code_hash = filemd5("/path/to/get_all_items.zip")
}

resource "aws_lambda_function" "update_item" {
  function_name = "${var.application_name}-update-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn

  filename         = "/path/to/update_item.zip"
  source_code_hash = filemd5("/path/to/update_item.zip")
}

resource "aws_lambda_function" "complete_item" {
  function_name = "${var.application_name}-complete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn

  filename         = "/path/to/complete_item.zip"
  source_code_hash = filemd5("/path/to/complete_item.zip")
}

resource "aws_lambda_function" "delete_item" {
  function_name = "${var.application_name}-delete-item"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn

  filename         = "/path/to/delete_item.zip"
  source_code_hash = filemd5("/path/to/delete_item.zip")
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.application_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy" "dynamodb_policy" {
  name   = "${var.application_name}-dynamodb-policy"
  role   = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ],
        "Resource": "${aws_dynamodb_table.todo_table.arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_exec_role.name
}

resource "aws_iam_role" "apigateway_logging_role" {
  name = "${var.application_name}-api-gateway-log-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "apigateway.amazonaws.com"
        },
        "Effect": "Allow"
      }
    ]
  })
}

resource "aws_iam_policy" "apigateway_logging_policy" {
  name   = "${var.application_name}-api-gateway-logging-policy"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apigateway_logging_role_policy_attachment" {
  role       = aws_iam_role.apigateway_logging_role.name
  policy_arn = aws_iam_policy.apigateway_logging_policy.arn
}

resource "aws_amplify_app" "frontend" {
  name       = "${var.application_name}-frontend"
  repository = "https://github.com/username/repository"
  
  build_spec = jsonencode({
    version: 0.1,
    phases: {
      preBuild: {
        commands: ["npm install"]
      },
      build: {
        commands: ["npm run build"]
      }
    },
    artifacts: {
      baseDirectory: "/build",
      files: ["**/*"]
    }
  })

  custom_rules {
    source    = "</^[^.]+$|.(?!(css|gif|ico|jpg|jpeg|js|png|txt|html|otf|ttf|woff|woff2)$)([^.]+$)/>"
    target    = "/index.html"
    status    = "404"
  }

  environment_variables {
    key   = "NODE_ENV"
    value = "production"
  }
}

resource "aws_amplify_branch" "frontend_master_branch" {
  app_id = aws_amplify_app.frontend.id
  branch_name = "master"
  enable_auto_build = true
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
  value = aws_amplify_branch.frontend_master_branch.url
}
