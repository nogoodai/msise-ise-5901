provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "Stack name for resource naming"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment name for resource tagging"
}

variable "project" {
  type        = string
  default     = "my-project"
  description = "Project name for resource tagging"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name                = "my-pool-${var.stack_name}"
  alias_attributes   = ["email"]
  email_configuration {
    email_verifying_message = "Your verification code is {####}."
    source_arn               = aws_iam_role.cognito_email.arn
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "my-pool-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                 = "my-client-${var.stack_name}"
  user_pool_id         = aws_cognito_user_pool.main.id
  generate_secret      = false
  allowed_oauth_flows  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls        = ["https://example.com/callback"]
  logout_urls          = ["https://example.com/logout"]
  supported_identity_providers = ["COGNITO"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "main" {
  domain               = "${var.stack_name}-${var.project}.auth.us-west-2.amazoncognito.com"
  user_pool_id         = aws_cognito_user_pool.main.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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
  read_capacity_units  = 5
  write_capacity_units = 5
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "my-api-${var.stack_name}"
  description = "API Gateway for serverless web application"
}

# API Gateway Resource and Method
resource "aws_api_gateway_resource" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "main" {
  rest_api_id         = aws_api_gateway_rest_api.main.id
  name                = "cognito-authorizer-${var.stack_name}"
  type                = "COGNITO_USER_POOLS"
  provider_arns       = [aws_cognito_user_pool.main.arn]
  identity_source     = "method.request.header.Authorization"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_method.get_item,
    aws_api_gateway_method.post_item,
    aws_api_gateway_method.put_item,
    aws_api_gateway_method.delete_item,
  ]
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"
}

# Lambda Function
resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "get-item-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_get_item.arn
}

resource "aws_lambda_function" "post_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "post-item-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_post_item.arn
}

resource "aws_lambda_function" "put_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "put-item-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_put_item.arn
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "delete-item-lambda-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_delete_item.arn
}

# Lambda Function Permissions
resource "aws_lambda_permission" "get_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "post_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "put_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.put_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "delete_item" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# Lambda Function Execution Roles
resource "aws_iam_role" "lambda_get_item" {
  name        = "lambda-get-item-role-${var.stack_name}"
  description = "Execution role for get item lambda function"

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
}

resource "aws_iam_role" "lambda_post_item" {
  name        = "lambda-post-item-role-${var.stack_name}"
  description = "Execution role for post item lambda function"

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
}

resource "aws_iam_role" "lambda_put_item" {
  name        = "lambda-put-item-role-${var.stack_name}"
  description = "Execution role for put item lambda function"

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
}

resource "aws_iam_role" "lambda_delete_item" {
  name        = "lambda-delete-item-role-${var.stack_name}"
  description = "Execution role for delete item lambda function"

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
}

# Lambda Function Policies
resource "aws_iam_policy" "lambda_get_item" {
  name        = "lambda-get-item-policy-${var.stack_name}"
  description = "Policy for get item lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:GetItem",
        ]
        Resource = aws_dynamodb_table.main.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_post_item" {
  name        = "lambda-post-item-policy-${var.stack_name}"
  description = "Policy for post item lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:PutItem",
        ]
        Resource = aws_dynamodb_table.main.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_put_item" {
  name        = "lambda-put-item-policy-${var.stack_name}"
  description = "Policy for put item lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:UpdateItem",
        ]
        Resource = aws_dynamodb_table.main.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_delete_item" {
  name        = "lambda-delete-item-policy-${var.stack_name}"
  description = "Policy for delete item lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.main.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_get_item" {
  role       = aws_iam_role.lambda_get_item.name
  policy_arn = aws_iam_policy.lambda_get_item.arn
}

resource "aws_iam_role_policy_attachment" "lambda_post_item" {
  role       = aws_iam_role.lambda_post_item.name
  policy_arn = aws_iam_policy.lambda_post_item.arn
}

resource "aws_iam_role_policy_attachment" "lambda_put_item" {
  role       = aws_iam_role.lambda_put_item.name
  policy_arn = aws_iam_policy.lambda_put_item.arn
}

resource "aws_iam_role_policy_attachment" "lambda_delete_item" {
  role       = aws_iam_role.lambda_delete_item.name
  policy_arn = aws_iam_policy.lambda_delete_item.arn
}

# Amplify App
resource "aws_amplify_app" "main" {
  name        = "my-app-${var.stack_name}"
  description = "Amplify app for serverless web application"
}

# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
}

# IAM Roles and Policies for API Gateway and Amplify
resource "aws_iam_role" "api_gateway" {
  name        = "api-gateway-role-${var.stack_name}"
  description = "Execution role for API Gateway"

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
}

resource "aws_iam_role" "amplify" {
  name        = "amplify-role-${var.stack_name}"
  description = "Execution role for Amplify"

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
}

resource "aws_iam_policy" "api_gateway" {
  name        = "api-gateway-policy-${var.stack_name}"
  description = "Policy for API Gateway"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_policy" "amplify" {
  name        = "amplify-policy-${var.stack_name}"
  description = "Policy for Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:CreateBranch",
          "amplify:DeleteBranch",
        ]
        Resource = aws_amplify_app.main.arn
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.main.arn
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "lambda_function_arns" {
  value = [
    aws_lambda_function.get_item.arn,
    aws_lambda_function.post_item.arn,
    aws_lambda_function.put_item.arn,
    aws_lambda_function.delete_item.arn,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.main.branch_name
}
