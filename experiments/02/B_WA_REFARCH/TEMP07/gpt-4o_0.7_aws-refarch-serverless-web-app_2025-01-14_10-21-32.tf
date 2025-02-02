terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The stack name used for naming resources"
  default     = "my-stack"
}

variable "github_repository" {
  description = "GitHub repository for the Amplify app"
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.stack_name}-auth-domain"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "${var.stack_name}-app-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  allowed_oauth_flows_user_pool_client = true
}

resource "aws_dynamodb_table" "todo_table" {
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

  tags = {
    Name        = "${var.stack_name}-todo-table"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name} application"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_stage" "stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_logs.arn
    format          = "$context.identity.sourceIp"
  }

  tags = {
    Name        = "${var.stack_name}-api-stage"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
}

resource "aws_cloudwatch_log_group" "api_logs" {
  name              = "/aws/api-gateway/${var.stack_name}-api"
  retention_in_days = 14

  tags = {
    Name        = "${var.stack_name}-api-logs"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "crud_functions" {
  count         = length(local.lambda_functions)
  function_name = "${var.stack_name}-${local.lambda_functions[count.index].name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-${local.lambda_functions[count.index].name}"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

locals {
  lambda_functions = [
    { name = "add-item", method = "POST", path = "/item" },
    { name = "get-item", method = "GET", path = "/item/{id}" },
    { name = "get-all-items", method = "GET", path = "/item" },
    { name = "update-item", method = "PUT", path = "/item/{id}" },
    { name = "complete-item", method = "POST", path = "/item/{id}/done" },
    { name = "delete-item", method = "DELETE", path = "/item/{id}" },
  ]
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-exec-role"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  policy_arn = aws_iam_policy.dynamodb_crud_policy.arn
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_policy" "dynamodb_crud_policy" {
  name        = "${var.stack_name}-dynamodb-crud-policy"
  description = "IAM policy for Lambda to perform CRUD operations on DynamoDB"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
    ]
  })
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.stack_name}-amplify-app"

  repository    = var.github_repository
  oauth_token   = data.aws_secretsmanager_secret_version.github_token.secret_string

  build_spec = jsonencode({
    version = "1.0"
    frontend = {
      phases = {
        preBuild = {
          commands = ["npm install"]
        }
        build = {
          commands = ["npm run build"]
        }
      }
      artifacts = {
        baseDirectory = "/build"
        files = ["**/*"]
      }
      cache = {
        paths = ["node_modules/**/*"]
      }
    }
  })

  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_branch" "master_branch" {
  app_id       = aws_amplify_app.amplify_app.id
  branch_name  = "master"
  enable_auto_build = true

  tags = {
    Name        = "${var.stack_name}-amplify-branch"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-api-gateway-role"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
  role       = aws_iam_role.api_gateway_role.name
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Environment = "production"
    Project     = "serverless-web-app"
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AWSAmplifyAdminAccess"
  role       = aws_iam_role.amplify_role.name
}

data "aws_secretsmanager_secret_version" "github_token" {
  secret_id = "github-token"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "amplify_app_url" {
  value = aws_amplify_app.amplify_app.default_domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}
