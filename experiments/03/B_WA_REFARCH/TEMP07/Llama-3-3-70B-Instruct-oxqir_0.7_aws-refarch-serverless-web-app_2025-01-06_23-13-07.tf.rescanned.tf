provider "aws" {
  region = "us-west-2"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "todo-user-pool"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
    from_email_address    = "no-reply@example.com"
  }
  alias_attributes     = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration     = "OPTIONAL"

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "todo-user-pool"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "todo-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  tags = {
    Name        = "todo-user-pool-client"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "todo-app"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB table
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${aws_cognito_user_pool.this.name}"
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
  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "todo-api"
  description = "API for Todo application"
  minimum_compression_size = 0

  tags = {
    Name        = "todo-api"
    Environment = "prod"
    Project     = "todo-app"
  }
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
  api_key_required = true
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_method" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_method" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get.arn}/invocations"
}

resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.post.arn}/invocations"
}

resource "aws_api_gateway_integration" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.put.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "todo-api-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.get, aws_api_gateway_integration.post, aws_api_gateway_integration.put, aws_api_gateway_integration.delete]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  name         = "todo-api-usage-plan"
  description  = "Usage plan for Todo API"
}

resource "aws_api_gateway_usage_plan_key" "this" {
  usage_plan_id = aws_api_gateway_usage_plan.this.id
  key_type      = "API_KEY"
  key           = aws_api_gateway_api_key.this.id
}

resource "aws_api_gateway_api_key" "this" {
  name        = "todo-api-key"
  description = "API key for Todo API"
}

# Lambda functions
resource "aws_lambda_function" "get" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_get.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "todo-get-item"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "post" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_post.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "todo-add-item"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "put" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_put.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "todo-update-item"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "delete" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_delete.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "todo-delete-item"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# IAM roles and policies
resource "aws_iam_role" "lambda_get" {
  name        = "todo-lambda-get-role"
  description = "Role for Todo Lambda get function"
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
    Name        = "todo-lambda-get-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "lambda_get" {
  name        = "todo-lambda-get-policy"
  description = "Policy for Todo Lambda get function"
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
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })

  tags = {
    Name        = "todo-lambda-get-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_get" {
  role       = aws_iam_role.lambda_get.name
  policy_arn = aws_iam_policy.lambda_get.arn
}

resource "aws_iam_role" "lambda_post" {
  name        = "todo-lambda-post-role"
  description = "Role for Todo Lambda post function"
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
    Name        = "todo-lambda-post-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "lambda_post" {
  name        = "todo-lambda-post-policy"
  description = "Policy for Todo Lambda post function"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
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
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })

  tags = {
    Name        = "todo-lambda-post-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_post" {
  role       = aws_iam_role.lambda_post.name
  policy_arn = aws_iam_policy.lambda_post.arn
}

resource "aws_iam_role" "lambda_put" {
  name        = "todo-lambda-put-role"
  description = "Role for Todo Lambda put function"
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
    Name        = "todo-lambda-put-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "lambda_put" {
  name        = "todo-lambda-put-policy"
  description = "Policy for Todo Lambda put function"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
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
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })

  tags = {
    Name        = "todo-lambda-put-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_put" {
  role       = aws_iam_role.lambda_put.name
  policy_arn = aws_iam_policy.lambda_put.arn
}

resource "aws_iam_role" "lambda_delete" {
  name        = "todo-lambda-delete-role"
  description = "Role for Todo Lambda delete function"
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
    Name        = "todo-lambda-delete-role"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "lambda_delete" {
  name        = "todo-lambda-delete-policy"
  description = "Policy for Todo Lambda delete function"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:DeleteItem",
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
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })

  tags = {
    Name        = "todo-lambda-delete-policy"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_delete" {
  role       = aws_iam_role.lambda_delete.name
  policy_arn = aws_iam_policy.lambda_delete.arn
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "The ID of the Cognito User Pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.this.id
  description = "The ID of the Cognito User Pool Client"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.this.name
  description = "The name of the DynamoDB Table"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.this.id
  description = "The ID of the API Gateway"
}

output "api_gateway_deployment_id" {
  value       = aws_api_gateway_deployment.this.id
  description = "The ID of the API Gateway Deployment"
}

output "lambda_function_get_arn" {
  value       = aws_lambda_function.get.arn
  description = "The ARN of the Lambda function for GET requests"
}

output "lambda_function_post_arn" {
  value       = aws_lambda_function.post.arn
  description = "The ARN of the Lambda function for POST requests"
}

output "lambda_function_put_arn" {
  value       = aws_lambda_function.put.arn
  description = "The ARN of the Lambda function for PUT requests"
}

output "lambda_function_delete_arn" {
  value       = aws_lambda_function.delete.arn
  description = "The ARN of the Lambda function for DELETE requests"
}
