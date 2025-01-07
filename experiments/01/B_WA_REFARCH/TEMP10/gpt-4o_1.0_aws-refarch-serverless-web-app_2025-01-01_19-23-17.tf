terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy the infrastructure."
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The application stack name for naming resources."
  default     = "my-app-stack"
}

variable "github_repo" {
  description = "The GitHub repository for the Amplify application."
}

resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.stack_name}-user-pool"
  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  callback_urls              = ["https://${var.stack_name}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"]

  tags = {
    Name        = "${var.stack_name}-client"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain      = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
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
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_api" "api" {
  name                 = "${var.stack_name}-api"
  protocol_type        = "HTTP"

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_stage" "stage" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "prod"
  auto_deploy = true

  tags = {
    Name        = "${var.stack_name}-stage"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.api.id
  authorizer_type  = "JWT"
  identity_source  = ["$request.header.Authorization"]
  issuer           = aws_cognito_user_pool.user_pool.endpoint
  name             = "${var.stack_name}-authorizer"
  audience         = [aws_cognito_user_pool_client.user_pool_client.id]
}

resource "aws_lambda_function" "todo_lambda" {
  for_each = {
    "add_item"    = "POST /item"
    "get_item"    = "GET /item/{id}"
    "get_all"     = "GET /item"
    "update_item" = "PUT /item/{id}"
    "complete"    = "POST /item/{id}/done"
    "delete"      = "DELETE /item/{id}"
  }

  function_name = "${var.stack_name}-${each.key}"
  runtime       = "nodejs12.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "${var.stack_name}-${each.key}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-exec-role"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "xray:PutTelemetryRecords",
          "xray:PutTraceSegments"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_amplify_app" "frontend" {
  name               = "${var.stack_name}-frontend"
  repository         = var.github_repo
  build_spec         = file("buildspec.yml")

  oauth_token {
    token = var.github_token
  }

  tags = {
    Name        = "${var.stack_name}-frontend"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "master"

  tags = {
    Name        = "${var.stack_name}-frontend-master"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "apigateway_role" {
  name = "${var.stack_name}-apigateway-role"

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
    Name        = "${var.stack_name}-apigateway-role"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "apigateway_policy" {
  name = "${var.stack_name}-apigateway-policy"
  role = aws_iam_role.apigateway_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = {
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:*"
    }
  })
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = {
      Effect = "Allow"
      Action = [
        "amplify:*"
      ]
      Resource = "*"
    }
  })
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_endpoint" {
  description = "The endpoint URL of the API Gateway"
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "amplify_app_id" {
  description = "The ID of the Amplify application"
  value       = aws_amplify_app.frontend.id
}
