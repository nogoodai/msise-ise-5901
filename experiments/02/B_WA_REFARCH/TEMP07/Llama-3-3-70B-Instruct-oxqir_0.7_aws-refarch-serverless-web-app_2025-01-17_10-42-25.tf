terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/my-repo"
  description = "The GitHub repository URL"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch name"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                     = "my-user-pool-${var.stack_name}"
  email_configuration = {
    email = "noreply@example.com"
  }
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  auto_verified_attributes = ["email"]
  password_policy = {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "my-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "my-user-pool-client-${var.stack_name}"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "my-domain-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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
  name        = "my-api-${var.stack_name}"
  description = "My API"
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "my-authorizer-${var.stack_name}"
  rest_api_id    = aws_api_gateway_rest_api.this.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

# Lambda Functions
resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "get-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "update-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "delete-item-${var.stack_name}"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
}

# API Gateway Integration
resource "aws_api_gateway_integration" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:function:get-item-${var.stack_name}/invocations"
}

resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:function:add-item-${var.stack_name}/invocations"
}

resource "aws_api_gateway_integration" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:function:update-item-${var.stack_name}/invocations"
}

resource "aws_api_gateway_integration" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:function:delete-item-${var.stack_name}/invocations"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "my-app-${var.stack_name}"
  description = "My Amplify App"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_backend_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment = "prod"
  backend_environment_arn = aws_amplify_backend_environment.this.arn
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "api-gateway-exec-${var.stack_name}"
  description = "API Gateway execution role"
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

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "api-gateway-policy-${var.stack_name}"
  description = "API Gateway policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:log-group:/aws/apigateway/${aws_api_gateway_rest_api.this.name}"
        Effect = "Allow"
      },
      {
        Action = "logs:CreateLogStream"
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:log-group:/aws/apigateway/${aws_api_gateway_rest_api.this.name}"
        Effect = "Allow"
      },
      {
        Action = "logs:PutLogEvents"
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:log-group:/aws/apigateway/${aws_api_gateway_rest_api.this.name}"
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "lambda-exec-${var.stack_name}"
  description = "Lambda execution role"
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

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-policy-${var.stack_name}"
  description = "Lambda policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:log-group:/aws/lambda/${aws_lambda_function.get_item.function_name}"
        Effect = "Allow"
      },
      {
        Action = "logs:CreateLogStream"
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:log-group:/aws/lambda/${aws_lambda_function.get_item.function_name}"
        Effect = "Allow"
      },
      {
        Action = "logs:PutLogEvents"
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:log-group:/aws/lambda/${aws_lambda_function.get_item.function_name}"
        Effect = "Allow"
      },
      {
        Action = "dynamodb:GetItem"
        Resource = aws_dynamodb_table.this.arn
        Effect = "Allow"
      },
      {
        Action = "dynamodb:PutItem"
        Resource = aws_dynamodb_table.this.arn
        Effect = "Allow"
      },
      {
        Action = "dynamodb:UpdateItem"
        Resource = aws_dynamodb_table.this.arn
        Effect = "Allow"
      },
      {
        Action = "dynamodb:DeleteItem"
        Resource = aws_dynamodb_table.this.arn
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "amplify-exec-${var.stack_name}"
  description = "Amplify execution role"
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

resource "aws_iam_policy" "amplify_policy" {
  name        = "amplify-policy-${var.stack_name}"
  description = "Amplify policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "amplify:CreateApp"
        Resource = aws_amplify_app.this.arn
        Effect = "Allow"
      },
      {
        Action = "amplify:CreateBranch"
        Resource = aws_amplify_app.this.arn
        Effect = "Allow"
      },
      {
        Action = "amplify:CreateBackendEnvironment"
        Resource = aws_amplify_app.this.arn
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "lambda_function_name" {
  value = aws_lambda_function.get_item.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
