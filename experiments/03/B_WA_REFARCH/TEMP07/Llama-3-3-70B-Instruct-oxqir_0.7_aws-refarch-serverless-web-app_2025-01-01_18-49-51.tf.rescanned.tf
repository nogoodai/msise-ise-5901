provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the application"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
  description = "The name of the stack"
}

variable "github_repos" {
  type        = string
  default     = "https://github.com/username/todo-repo"
  description = "The GitHub repository URL"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.application_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration = "OFF"

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.application_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain               = "${var.application_name}.${var.stack_name}"
  user_pool_id         = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name                = "todo-table-${var.stack_name}"
  billing_mode        = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  hash_key             = "cognito-username"
  range_key            = "id"
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
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name                = "${var.application_name}-api"
  description         = "API for ${var.application_name} application"
  minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-api"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_method" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "${var.application_name}-authorizer"
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id    = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestTime = "$context.requestTime"
    })
  }

  tags = {
    Name        = "prod"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "api-gateway-logs"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_method.post_item, aws_api_gateway_method.get_item, aws_api_gateway_method.get_all_items, aws_api_gateway_method.put_item, aws_api_gateway_method.delete_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_usage_plan" "this" {
  name         = "${var.application_name}-usage-plan"
  description  = "Usage plan for ${var.application_name} application"

  api_keys     = [aws_api_gateway_api_key.this.id]
}

resource "aws_api_gateway_api_key" "this" {
  name        = "${var.application_name}-api-key"
  description = "API key for ${var.application_name} application"
}

resource "aws_api_gateway_usage_plan_key" "this" {
  usage_plan_id = aws_api_gateway_usage_plan.this.id
  key_id        = aws_api_gateway_api_key.this.id
  key_type      = "API_KEY"
}

# Lambda Function
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-add-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-get-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-get-all-items"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "put_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-put-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-put-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-delete-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

# API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.add_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.get_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_all_items.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.get_all_items.function_name}/invocations"
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.put_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${aws_lambda_function.delete_item.function_name}/invocations"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = var.application_name
  description = "Amplify app for ${var.application_name} application"
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec" {
  name        = "${var.application_name}-lambda-exec"
  description = "Lambda execution role for ${var.application_name} application"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-lambda-exec"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_exec" {
  name   = "${var.application_name}-lambda-exec-policy"
  role   = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.this.arn
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.application_name}-api-gateway-exec"
  description = "API Gateway execution role for ${var.application_name} application"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-api-gateway-exec"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_exec" {
  name   = "${var.application_name}-api-gateway-exec-policy"
  role   = aws_iam_role.api_gateway_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.application_name}-amplify-exec"
  description = "Amplify execution role for ${var.application_name} application"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-amplify-exec"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "amplify_exec" {
  name   = "${var.application_name}-amplify-exec-policy"
  role   = aws_iam_role.amplify_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*"
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
  description = "The ID of the Cognito User Pool"
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
  description = "The ID of the Cognito User Pool Client"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
  description = "The name of the DynamoDB Table"
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
  description = "The ID of the API Gateway"
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_stage.prod.stage_name
  description = "The name of the API Gateway Stage"
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.put_item.function_name,
    aws_lambda_function.delete_item.function_name
  ]
  description = "The names of the Lambda Functions"
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
  description = "The ID of the Amplify App"
}

output "amplify_branch_name" {
  value = aws_amplify_branch.master.branch_name
  description = "The name of the Amplify Branch"
}
