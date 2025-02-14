# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# Set AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Set variables
variable "stack_name" {
  type        = string
  default     = "serverless-web-app"
  description = "The name of the stack"
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

# Create Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                     = "${var.stack_name}-user-pool"
  email_verification_subject = "Your verification code"
  email_verification_message  = "Please verify your email address by clicking the link below: {##VerifyEmail##}"
  alias_attributes           = ["email"]
  auto_verified_attributes   = ["email"]
  mfa_configuration          = "OPTIONAL"
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = "serverless-web-app"
  }

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
}

# Create Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.this.id
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  hash_key       = "cognito-username"
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  global_secondary_index {
    name               = "id-index"
    hash_key           = "id"
    projection_type    = "ALL"
  }
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

# Create API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "Serverless Web App API"
  minimum_compression_size = 0
  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  api_key_required = true
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
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

resource "aws_api_gateway_authorizer" "this" {
  name          = "${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_method.post, aws_api_gateway_method.get, aws_api_gateway_method.put, aws_api_gateway_method.delete]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
  tags = {
    Name        = "${var.stack_name}-deployment"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.stack_name}-usage-plan"
  description = "Serverless Web App Usage Plan"

  quota_settings {
    limit  = 5000
    offset = 2
    period  = "DAY"
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

# Create Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda/add_item.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda/get_item.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-get-item"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda/get_all_items.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-get-all-items"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda/update_item.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-update-item"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda/complete_item.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-complete-item"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda/delete_item.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-delete-item"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

# Create API Gateway Integrations
resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

# Create Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.stack_name}-amplify-app"
  description = "Serverless Web App Amplify App"
  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  environment = "prod"
}

# Create IAM Roles and Policies
resource "aws_iam_role" "lambda" {
  name        = "${var.stack_name}-lambda-execution-role"
  description = "Execution role for Lambda functions"
  tags = {
    Name        = "${var.stack_name}-lambda-execution-role"
    Environment = "prod"
    Project     = "serverless-web-app"
  }

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

resource "aws_iam_policy" "lambda" {
  name        = "${var.stack_name}-lambda-execution-policy"
  description = "Execution policy for Lambda functions"
  tags = {
    Name        = "${var.stack_name}-lambda-execution-policy"
    Environment = "prod"
    Project     = "serverless-web-app"
  }

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
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

resource "aws_iam_role" "api_gateway" {
  name        = "${var.stack_name}-api-gateway-execution-role"
  description = "Execution role for API Gateway"
  tags = {
    Name        = "${var.stack_name}-api-gateway-execution-role"
    Environment = "prod"
    Project     = "serverless-web-app"
  }

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

resource "aws_iam_policy" "api_gateway" {
  name        = "${var.stack_name}-api-gateway-execution-policy"
  description = "Execution policy for API Gateway"
  tags = {
    Name        = "${var.stack_name}-api-gateway-execution-policy"
    Environment = "prod"
    Project     = "serverless-web-app"
  }

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

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

resource "aws_iam_role" "amplify" {
  name        = "${var.stack_name}-amplify-execution-role"
  description = "Execution role for Amplify"
  tags = {
    Name        = "${var.stack_name}-amplify-execution-role"
    Environment = "prod"
    Project     = "serverless-web-app"
  }

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

resource "aws_iam_policy" "amplify" {
  name        = "${var.stack_name}-amplify-execution-policy"
  description = "Execution policy for Amplify"
  tags = {
    Name        = "${var.stack_name}-amplify-execution-policy"
    Environment = "prod"
    Project     = "serverless-web-app"
  }

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Resource = "*"
        Effect    = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

# Output values
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

output "lambda_function_names" {
  value = [
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.update_item.function_name,
    aws_lambda_function.complete_item.function_name,
    aws_lambda_function.delete_item.function_name,
  ]
  description = "The names of the Lambda Functions"
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
  description = "The ID of the Amplify App"
}

output "amplify_branch_name" {
  value = aws_amplify_branch.this.branch_name
  description = "The name of the Amplify Branch"
}
