# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
  required_version = ">= 1.0.0"
}

# Provider configuration
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  description = "The GitHub repository for the frontend code"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch for the frontend code"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  email_configuration {
    email_sending_account = "DEVELOPER"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls = ["https://${var.stack_name}.auth.us-west-2.amazoncognito.com/oauth2/idpresponse"]
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB table
resource "aws_dynamodb_table" "this" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  key_schema = [
    {
      attribute_name = "cognito-username"
      key_type       = "HASH"
    },
    {
      attribute_name = "id"
      key_type       = "RANGE"
    }
  ]
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"
  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_authorizer" "this" {
  name          = "${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  provider_arns = [aws_cognito_user_pool.this.arn]
}

# API Gateway resource and method
resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}
resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}
resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

# API Gateway integration with Lambda function
resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type        = "AWS"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.stack_name}-get-item/invocations"
  request_templates = {
    "application/json" = "{\"body\": $input.json('$')}"
  }
}
resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "AWS"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.stack_name}-add-item/invocations"
  request_templates = {
    "application/json" = "{\"body\": $input.json('$')}"
  }
}

# Lambda functions
resource "aws_lambda_function" "get_item" {
  filename      = "get-item.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_get_item.arn
  memory_size   = 1024
  timeout       = 60
}
resource "aws_lambda_permission" "get_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*/${aws_api_gateway_resource.this.path_part}"
}
resource "aws_lambda_function" "add_item" {
  filename      = "add-item.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_add_item.arn
  memory_size   = 1024
  timeout       = 60
}
resource "aws_lambda_permission" "add_item" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*/${aws_api_gateway_resource.this.path_part}"
}

# Amplify app
resource "aws_amplify_app" "this" {
  name        = "${var.stack_name}-app"
  description = "Amplify app for ${var.stack_name}"
}
resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

# IAM roles and policies
resource "aws_iam_role" "lambda_get_item" {
  name        = "${var.stack_name}-lambda-get-item"
  description = "IAM role for Lambda get item function"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}
resource "aws_iam_policy" "lambda_get_item" {
  name        = "${var.stack_name}-lambda-get-item-policy"
  description = "IAM policy for Lambda get item function"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
        ]
        Resource = aws_dynamodb_table.this.arn
        Effect    = "Allow"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/lambda/${var.stack_name}-get-item"
        Effect    = "Allow"
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_get_item" {
  role       = aws_iam_role.lambda_get_item.name
  policy_arn = aws_iam_policy.lambda_get_item.arn
}

resource "aws_iam_role" "lambda_add_item" {
  name        = "${var.stack_name}-lambda-add-item"
  description = "IAM role for Lambda add item function"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}
resource "aws_iam_policy" "lambda_add_item" {
  name        = "${var.stack_name}-lambda-add-item-policy"
  description = "IAM policy for Lambda add item function"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.this.arn
        Effect    = "Allow"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/lambda/${var.stack_name}-add-item"
        Effect    = "Allow"
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_add_item" {
  role       = aws_iam_role.lambda_add_item.name
  policy_arn = aws_iam_policy.lambda_add_item.arn
}

resource "aws_iam_role" "api_gateway" {
  name        = "${var.stack_name}-api-gateway"
  description = "IAM role for API Gateway"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}
resource "aws_iam_policy" "api_gateway" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "IAM policy for API Gateway"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/apigateway/${var.stack_name}-api"
        Effect    = "Allow"
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

resource "aws_iam_role" "amplify" {
  name        = "${var.stack_name}-amplify"
  description = "IAM role for Amplify"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}
resource "aws_iam_policy" "amplify" {
  name        = "${var.stack_name}-amplify-policy"
  description = "IAM policy for Amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:aws:s3:::amplify-${var.stack_name}-app/*"
        Effect    = "Allow"
      },
    ]
  })
}
resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}
output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}
output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}
output "api_gateway_stage_name" {
  value = "prod"
}
output "lambda_function_arn_get_item" {
  value = aws_lambda_function.get_item.arn
}
output "lambda_function_arn_add_item" {
  value = aws_lambda_function.add_item.arn
}
output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
