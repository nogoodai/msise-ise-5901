provider "aws" {
  region = "us-east-1"
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

variable "application_name" {
  type        = string
  default     = "my-application"
  description = "The name of the application"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "The GitHub token for Amplify"
}

variable "github_repo" {
  type        = string
  description = "The GitHub repository for Amplify"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch for Amplify"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name = "${var.application_name}-${var.stack_name}"
  mfa_configuration = "OFF"
  alias_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                                 = "${var.application_name}-${var.stack_name}-client"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
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

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.application_name}-${var.stack_name}"
  description = "API Gateway for ${var.application_name}-${var.stack_name}"

  minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = var.stack_name
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

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.post_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.put_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "this" {
  name          = "${var.application_name}-${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.post_item, aws_api_gateway_integration.get_item, aws_api_gateway_integration.put_item, aws_api_gateway_integration.delete_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.application_name}-${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.application_name}-${var.stack_name}"

  quota {
    limit  = 5000
    period = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-usage-plan"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "post_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-post-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-post-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-get-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "put_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-put-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-put-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-delete-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.application_name}-${var.stack_name}"
  description = "Amplify app for ${var.application_name}-${var.stack_name}"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway-exec"
  description = "API Gateway execution role for ${var.application_name}-${var.stack_name}"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-exec"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_exec" {
  name   = "${var.application_name}-${var.stack_name}-api-gateway-exec-policy"
  role   = aws_iam_role.api_gateway_exec.id
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
      }
    ]
  })
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.application_name}-${var.stack_name}-lambda-exec"
  description = "Lambda execution role for ${var.application_name}-${var.stack_name}"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-exec"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "lambda_exec" {
  name   = "${var.application_name}-${var.stack_name}-lambda-exec-policy"
  role   = aws_iam_role.lambda_exec.id
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
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.this.arn
        Effect    = "Allow"
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.application_name}-${var.stack_name}-amplify-exec"
  description = "Amplify execution role for ${var.application_name}-${var.stack_name}"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-exec"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "amplify_exec" {
  name   = "${var.application_name}-${var.stack_name}-amplify-exec-policy"
  role   = aws_iam_role.amplify_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "The ID of the Cognito User Pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.this.id
  description = "The ID of the Cognito User Pool Client"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.this.id
  description = "The ID of the API Gateway"
}

output "api_gateway_deployment_id" {
  value       = aws_api_gateway_deployment.this.id
  description = "The ID of the API Gateway Deployment"
}

output "lambda_function_post_item_arn" {
  value       = aws_lambda_function.post_item.arn
  description = "The ARN of the post item Lambda function"
}

output "lambda_function_get_item_arn" {
  value       = aws_lambda_function.get_item.arn
  description = "The ARN of the get item Lambda function"
}

output "lambda_function_put_item_arn" {
  value       = aws_lambda_function.put_item.arn
  description = "The ARN of the put item Lambda function"
}

output "lambda_function_delete_item_arn" {
  value       = aws_lambda_function.delete_item.arn
  description = "The ARN of the delete item Lambda function"
}

output "amplify_app_id" {
  value       = aws_amplify_app.this.id
  description = "The ID of the Amplify App"
}

output "amplify_branch_id" {
  value       = aws_amplify_branch.this.id
  description = "The ID of the Amplify Branch"
}
