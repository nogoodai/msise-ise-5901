provider "aws" {
  region = "us-east-1"
  version = "4.64.0"
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "The GitHub token for authentication"
}

variable "github_repo" {
  type        = string
  default     = "my-repo"
  description = "The name of the GitHub repository"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The name of the GitHub branch"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                     = "${var.stack_name}-user-pool"
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                 = "${var.stack_name}-user-pool-client"
  user_pool_id         = aws_cognito_user_pool.this.id
  generate_secret      = false
  allowed_oauth_flows  = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers = ["COGNITO"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}-auth"
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
  point_in_time_recovery {
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
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
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
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
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
  name          = "${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.post_item, aws_api_gateway_integration.get_item, aws_api_gateway_integration.put_item, aws_api_gateway_integration.delete_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
  stage_description = "Production stage for ${var.stack_name}"
  tags = {
    Name        = "${var.stack_name}-deployment"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for ${var.stack_name}"
  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "prod"
    Project     = var.stack_name
  }

  quota {
    limit  = 5000
    offset = 2
    period  = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_deployment.this.stage_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.stack_name}-app"
  description = "Amplify app for ${var.stack_name}"
  tags = {
    Name        = "${var.stack_name}-app"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_webhook" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  description = "Webhook for ${var.stack_name}"
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec"
  description = "API Gateway execution role for ${var.stack_name}"
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
    Name        = "${var.stack_name}-api-gateway-exec"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "API Gateway policy for ${var.stack_name}"
  policy      = jsonencode({
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
  tags = {
    Name        = "${var.stack_name}-api-gateway-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_attach" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.stack_name}-amplify-exec"
  description = "Amplify execution role for ${var.stack_name}"
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
    Name        = "${var.stack_name}-amplify-exec"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Amplify policy for ${var.stack_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.stack_name}-amplify-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_attach" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec"
  description = "Lambda execution role for ${var.stack_name}"
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
    Name        = "${var.stack_name}-lambda-exec"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Lambda policy for ${var.stack_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.stack_name}-lambda-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "The ID of the Cognito user pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.this.id
  description = "The ID of the Cognito user pool client"
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.this.arn
  description = "The ARN of the DynamoDB table"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.this.id
  description = "The ID of the API Gateway"
}

output "api_gateway_url" {
  value       = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${aws_region}.amazonaws.com/prod/item"
  description = "The URL of the API Gateway"
}

output "amplify_app_id" {
  value       = aws_amplify_app.this.id
  description = "The ID of the Amplify app"
}

output "amplify_app_url" {
  value       = "https://${aws_amplify_app.this.id}.amplifyapp.com"
  description = "The URL of the Amplify app"
}
