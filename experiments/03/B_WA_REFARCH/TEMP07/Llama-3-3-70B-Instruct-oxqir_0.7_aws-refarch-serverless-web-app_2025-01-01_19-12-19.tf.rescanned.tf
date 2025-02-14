# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "The environment of the stack"
}

variable "project" {
  type        = string
  default     = "my-project"
  description = "The name of the project"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/my-username/my-repo"
  description = "The GitHub repository URL"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch name"
}

# Create Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "this" {
  name                = "${var.project}-user-pool"
  email_configuration = {
    email_sending_account = "COGNITO_DEFAULT"
  }
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  alias_attributes = ["email"]
  mfa_configuration = "OPTIONAL"
  tags = {
    Name        = "${var.project}-user-pool"
    Environment = var.environment
    Project     = var.project
  }
}

# Create Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.project}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Create custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.project}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# Create DynamoDB table for data storage
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${var.stack_name}"
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
    Environment = var.environment
    Project     = var.project
  }
}

# Create API Gateway for serving API requests
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.project}-api"
  description = "API for ${var.project}"
  minimum_compression_size = 0
  tags = {
    Name        = "${var.project}-api"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_authorizer" "this" {
  name          = "${var.project}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
}

# Create API Gateway stage and usage plan
resource "aws_api_gateway_stage" "this" {
  stage_name    = var.environment
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  xray_tracing_enabled = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.this.arn
    format          = "{\"requestId\":\"$context.requestId\",\"ip\":\"$context.identity.sourceIp\",\"user\":\"$context.identity.username\",\"caller\":\"$context.identity.caller\",\"requestTime\":\"$context.requestTime\",\"httpMethod\":\"$context.httpMethod\",\"resourcePath\":\"$context.resourcePath\",\"status\":\"$context.status\",\"protocol\":\"$context.protocol\",\"responseLength\":\"$context.responseLength\"}"
  }
  tags = {
    Name        = var.environment
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  name         = "${var.project}-usage-plan"
  description  = "Usage plan for ${var.project}"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }
  quota {
    limit  = 5000
    offset = 2
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
  tags = {
    Name        = "${var.project}-usage-plan"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.this]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = var.environment
}

# Create Lambda functions for CRUD operations
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = [aws_security_group.this.id]
    subnet_ids         = [aws_subnet.this.id]
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.project}-add-item"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = [aws_security_group.this.id]
    subnet_ids         = [aws_subnet.this.id]
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.project}-get-item"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = [aws_security_group.this.id]
    subnet_ids         = [aws_subnet.this.id]
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.project}-get-all-items"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = [aws_security_group.this.id]
    subnet_ids         = [aws_subnet.this.id]
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.project}-update-item"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = [aws_security_group.this.id]
    subnet_ids         = [aws_subnet.this.id]
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.project}-complete-item"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.project}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = [aws_security_group.this.id]
    subnet_ids         = [aws_subnet.this.id]
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.project}-delete-item"
    Environment = var.environment
    Project     = var.project
  }
}

# Create API Gateway integrations
resource "aws_api_gateway_integration" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

# Create API Gateway resource and method
resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

# Create CloudWatch log group
resource "aws_cloudwatch_log_group" "this" {
  name              = "${var.project}-api-gateway-log-group"
  retention_in_days = 30
  tags = {
    Name        = "${var.project}-api-gateway-log-group"
    Environment = var.environment
    Project     = var.project
  }
}

# Create Amplify app for frontend hosting
resource "aws_amplify_app" "this" {
  name        = "${var.project}-app"
  description = "Amplify app for ${var.project}"
  tags = {
    Name        = "${var.project}-app"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_backend_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment_name = var.environment
}

# Create IAM roles and policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.project}-api-gateway-exec"
  description = "API Gateway execution role for ${var.project}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
  tags = {
    Name        = "${var.project}-api-gateway-exec"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "api_gateway_exec" {
  name   = "${var.project}-api-gateway-exec-policy"
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
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.project}-lambda-exec"
  description = "Lambda execution role for ${var.project}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  tags = {
    Name        = "${var.project}-lambda-exec"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "lambda_exec" {
  name   = "${var.project}-lambda-exec-policy"
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
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      }
    ]
  })
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.project}-amplify-exec"
  description = "Amplify execution role for ${var.project}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
  tags = {
    Name        = "${var.project}-amplify-exec"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy" "amplify_exec" {
  name   = "${var.project}-amplify-exec-policy"
  role   = aws_iam_role.amplify_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetBackendEnvironment",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Output critical information
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.this.id
  description = "The ID of the Cognito user pool"
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.this.id
  description = "The ID of the Cognito user pool client"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.this.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.this.id
  description = "The ID of the API Gateway"
}

output "api_gateway_stage_name" {
  value       = aws_api_gateway_stage.this.stage_name
  description = "The name of the API Gateway stage"
}

output "lambda_function_names" {
  value       = [
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.update_item.function_name,
    aws_lambda_function.complete_item.function_name,
    aws_lambda_function.delete_item.function_name,
  ]
  description = "The names of the Lambda functions"
}

output "amplify_app_id" {
  value       = aws_amplify_app.this.id
  description = "The ID of the Amplify app"
}

output "amplify_branch_name" {
  value       = aws_amplify_branch.this.branch_name
  description = "The name of the Amplify branch"
}
