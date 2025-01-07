provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Variables
variable "stack_name" {
  type        = string
  description = "Stack name"
  default     = "my-stack"
}

variable "environment" {
  type        = string
  description = "Environment name"
  default     = "prod"
}

variable "project_name" {
  type        = string
  description = "Project name"
  default     = "my-project"
}

variable "github_repository" {
  type        = string
  description = "GitHub repository URL"
  default     = "https://github.com/user/repo"
}

variable "github_token" {
  type        = string
  description = "GitHub personal access token"
  sensitive   = true
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.project_name}-${var.stack_name}-${var.environment}-user-pool"
  alias_attributes   = ["email"]
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.project_name}-${var.stack_name}-${var.environment}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH", "CUSTOM_AUTH_FLOW_ONLY", "USER_SRP_AUTH"]
  allowed_o_auth_flows = ["authorization_code", "implicit"]
  allowed_o_auth_scopes = ["email", "phone", "openid"]
  allowed_o_auth_flows_user_pool_client = true
  supported_identity_providers = ["COGNITO"]
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "cognito_domain" {
  domain       = "${var.project_name}-${var.stack_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name         = "${var.project_name}-${var.stack_name}-${var.environment}-todo-table"
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
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-todo-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.project_name}-${var.stack_name}-${var.environment}-api-gateway"
  description = "API Gateway for ${var.project_name}"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "put_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "delete_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.lambda_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.lambda_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.put_method.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.lambda_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.delete_method.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.lambda_function.arn}/invocations"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_integration.post_integration, aws_api_gateway_integration.get_integration, aws_api_gateway_integration.put_integration, aws_api_gateway_integration.delete_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.project_name}-${var.stack_name}-${var.environment}-usage-plan"
  description = "Usage plan for ${var.project_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.api_deployment.stage_name
  }
  quota {
    limit  = 5000
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.project_name}-${var.stack_name}-${var.environment}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# Lambda Function
resource "aws_lambda_function" "lambda_function" {
  filename      = "lambda_function.zip"
  function_name = "${var.project_name}-${var.stack_name}-${var.environment}-lambda-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-lambda-function"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "lambda_role" {
  name        = "${var.project_name}-${var.stack_name}-${var.environment}-lambda-role"
  description = "Lambda role for ${var.project_name}"
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
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-${var.stack_name}-${var.environment}-lambda-policy"
  description = "Lambda policy for ${var.project_name}"
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
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
    ]
  })
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-lambda-policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = "${var.project_name}-${var.stack_name}-${var.environment}-amplify-app"
  description = "Amplify app for ${var.project_name}"
  platform    = "WEB"
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-amplify-app"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

resource "aws_amplify_webhook" "amplify_webhook" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = aws_amplify_branch.amplify_branch.branch_name
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.project_name}-${var.stack_name}-${var.environment}-api-gateway-role"
  description = "API Gateway role for ${var.project_name}"
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
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-api-gateway-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.project_name}-${var.stack_name}-${var.environment}-api-gateway-policy"
  description = "API Gateway policy for ${var.project_name}"
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
      },
    ]
  })
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-api-gateway-policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.project_name}-${var.stack_name}-${var.environment}-amplify-role"
  description = "Amplify role for ${var.project_name}"
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
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.project_name}-${var.stack_name}-${var.environment}-amplify-policy"
  description = "Amplify policy for ${var.project_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:CreateBranch",
          "amplify:DeleteBranch",
          "amplify:UpdateBranch",
        ]
        Resource = aws_amplify_app.amplify_app.arn
        Effect    = "Allow"
      },
    ]
  })
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-${var.environment}-amplify-policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.lambda_function.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.amplify_branch.branch_name
}
