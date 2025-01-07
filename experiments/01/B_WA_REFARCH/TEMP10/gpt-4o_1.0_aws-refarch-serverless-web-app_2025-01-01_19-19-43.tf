terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack"
  type        = string
  default     = "my-stack"
}

variable "amplify_source_repository" {
  description = "The source repository for Amplify"
  type        = string
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "user-pool-${var.stack_name}"

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
    Name        = "user-pool-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain       = "${var.stack_name}.domain.com"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  allowed_oauth_flows        = ["code", "implicit"]
  allowed_oauth_scopes       = ["email", "phone", "openid"]
  generate_secret            = false
  supported_identity_providers = ["COGNITO"]

  tags = {
    Name        = "client-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_dynamodb_table" "todo_table" {
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
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "api-${var.stack_name}"
  description = "API Gateway for the ${var.stack_name} stack"

  tags = {
    Name        = "api-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }

  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_stage" {
  stage_name           = "prod"
  rest_api_id          = aws_api_gateway_rest_api.api_gateway.id
  deployment_id        = aws_api_gateway_deployment.deployment.id
  description          = "Production stage"

  tags = {
    Name        = "api-stage-prod"
    Environment = "production"
    Project     = var.stack_name
  }

  xray_tracing_enabled = true

  settings {
    logging_level = "INFO"
    metrics_enabled = true
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
}

resource "aws_lambda_function" "lambda_function" {
  for_each = {
    "AddItem"     = "/item"
    "GetItem"     = "/item/{id}"
    "GetAllItems" = "/item"
    "UpdateItem"  = "/item/{id}"
    "CompleteItem" = "/item/{id}/done"
    "DeleteItem"  = "/item/{id}"
  }

  function_name = "lambda-${each.key}-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      "DYNAMODB_TABLE" = aws_dynamodb_table.todo_table.name
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "lambda-${each.key}-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role-${var.stack_name}"

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
    Name        = "lambda-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-policy-${var.stack_name}"
  description = "Policy to grant lambda permissions to access DynamoDB and publish metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

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
    Name        = "api-gateway-role-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "api-gateway-policy-${var.stack_name}"
  description = "Policy to enable API Gateway to write logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_amplify_app" "amplify_app" {
  name  = "amplify-${var.stack_name}"
  repository = var.amplify_source_repository
  oauth_token = "YOUR_OAUTH_TOKEN"

  build_spec = <<-YAML
    version: 1.0
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
          paths: []
  YAML

  environment_variables = {
    "AMPLIFY_MONOREPO_APP" = "true"
  }

  tags = {
    Name        = "amplify-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"

  enable_auto_build = true

  tags = {
    Name        = "amplify-branch-master-${var.stack_name}"
    Environment = "production"
    Project     = var.stack_name
  }
}

output "user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.user_pool.id
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.todo_table.arn
}

output "api_gateway_invoke_url" {
  description = "Invoke URL of the API Gateway"
  value       = aws_api_gateway_deployment.deployment.invoke_url
}

output "amplify_app_url" {
  description = "URL of the Amplify app"
  value       = aws_amplify_app.amplify_app.default_domain
}
