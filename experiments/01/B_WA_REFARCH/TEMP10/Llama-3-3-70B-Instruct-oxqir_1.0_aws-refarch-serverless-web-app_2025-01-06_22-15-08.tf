# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Variable for stack name
variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

# Create Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                     = "my-${var.stack_name}-user-pool"
  email_configuration      = {}
  email_verification_subject = "Your verification code"
  email_verification_message = "Your verification code is {####}. "
  alias_attributes          = []
  auto_verified_attributes = ["email"]
  username_attributes       = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "my-${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "my-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  tags = {
    Name        = "my-${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Create Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain = "my-${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.this.id
}

# Create DynamoDB Table
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
    Project     = "my-project"
  }
}

# Create IAM Role for API Gateway
resource "aws_iam_role" "api_gateway" {
  name        = "my-${var.stack_name}-api-gateway-role"
  description = "API Gateway Role"

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
    Name        = "my-${var.stack_name}-api-gateway-role"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Create IAM Policy for API Gateway
resource "aws_iam_policy" "api_gateway" {
  name        = "my-${var.stack_name}-api-gateway-policy"
  description = "API Gateway Policy"

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
  tags = {
    Name        = "my-${var.stack_name}-api-gateway-policy"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Attach IAM Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

# Create API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "my-${var.stack_name}-api"
  description = "API Gateway"
  tags = {
    Name        = "my-${var.stack_name}-api"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Create API Gateway Resource
resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

# Create API Gateway Method
resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
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

# Create API Gateway Authorizer
resource "aws_api_gateway_authorizer" "this" {
  name          = "my-${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
}

# Create API Gateway Deployment
resource "aws_api_gateway_deployment" "this" {
  depends_on  = [aws_api_gateway_method.post, aws_api_gateway_method.get, aws_api_gateway_method.put, aws_api_gateway_method.delete]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# Create API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "this" {
  name         = "my-${var.stack_name}-usage-plan"
  description  = "API Gateway Usage Plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_deployment.this.stage_name
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

# Create IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name        = "my-${var.stack_name}-lambda-role"
  description = "Lambda Role"

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
    Name        = "my-${var.stack_name}-lambda-role"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Create IAM Policy for Lambda
resource "aws_iam_policy" "lambda" {
  name        = "my-${var.stack_name}-lambda-policy"
  description = "Lambda Policy"

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
      }
    ]
  })
  tags = {
    Name        = "my-${var.stack_name}-lambda-policy"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# Create Lambda Function
resource "aws_lambda_function" "this" {
  filename      = "lambda_function_payload.zip"
  function_name = "my-${var.stack_name}-lambda"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
  tags = {
    Name        = "my-${var.stack_name}-lambda"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Create API Gateway Integration
resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:function:${aws_lambda_function.this.function_name}/invocations"
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:function:${aws_lambda_function.this.function_name}/invocations"
}

resource "aws_api_gateway_integration" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:function:${aws_lambda_function.this.function_name}/invocations"
}

resource "aws_api_gateway_integration" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:function:${aws_lambda_function.this.function_name}/invocations"
}

# Create Amplify App
resource "aws_amplify_app" "this" {
  name        = "my-${var.stack_name}-amplify-app"
  description = "Amplify App"
  tags = {
    Name        = "my-${var.stack_name}-amplify-app"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Create Amplify Branch
resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
  stage       = "PRODUCTION"
  enable_auto_build = true
  enable_pull_request_preview = true
  tags = {
    Name        = "my-${var.stack_name}-amplify-branch"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Create IAM Role for Amplify
resource "aws_iam_role" "amplify" {
  name        = "my-${var.stack_name}-amplify-role"
  description = "Amplify Role"

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
    Name        = "my-${var.stack_name}-amplify-role"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Create IAM Policy for Amplify
resource "aws_iam_policy" "amplify" {
  name        = "my-${var.stack_name}-amplify-policy"
  description = "Amplify Policy"

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
  tags = {
    Name        = "my-${var.stack_name}-amplify-policy"
    Environment = "prod"
    Project     = "my-project"
  }
}

# Attach IAM Policy to Amplify Role
resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

# Output
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "api_gateway_deployment_id" {
  value = aws_api_gateway_deployment.this.id
}

output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_branch_id" {
  value = aws_amplify_branch.this.id
}
