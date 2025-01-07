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
  default     = "serverless-web-app"
  description = "The name of the stack"
}

variable "application_name" {
  type        = string
  default     = "serverless-web-app"
  description = "The name of the application"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  username_attributes = ["email"]
  email_configuration {
    email_sending_account = "DEVELOPER"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls = [
    "https://${var.application_name}.auth.us-west-2.amazoncognito.com/oauth2/idpresponse",
  ]
  supported_identity_providers = ["COGNITO"]
  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.application_name}"
  user_pool_id = aws_cognito_user_pool.this.id
  tags = {
    Name        = "${var.stack_name}-user-pool-domain"
    Environment = "prod"
    Project     = var.application_name
  }
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
    },
  ]
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "${var.stack_name}-dynamodb-table"
    Environment = "prod"
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api-gateway"
  description = "API Gateway for ${var.application_name}"
  tags = {
    Name        = "${var.stack_name}-api-gateway"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "this" {
  name          = "${var.stack_name}-api-gateway-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
  tags = {
    Name        = "${var.stack_name}-api-gateway-authorizer"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
  tags = {
    Name        = "${var.stack_name}-api-gateway-resource"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  tags = {
    Name        = "${var.stack_name}-api-gateway-method-post-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  tags = {
    Name        = "${var.stack_name}-api-gateway-method-get-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_method" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  tags = {
    Name        = "${var.stack_name}-api-gateway-method-get-all-items"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  tags = {
    Name        = "${var.stack_name}-api-gateway-method-put-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_method" "post_done_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  tags = {
    Name        = "${var.stack_name}-api-gateway-method-post-done-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  tags = {
    Name        = "${var.stack_name}-api-gateway-method-delete-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_method.post_item,
    aws_api_gateway_method.get_item,
    aws_api_gateway_method.get_all_items,
    aws_api_gateway_method.put_item,
    aws_api_gateway_method.post_done_item,
    aws_api_gateway_method.delete_item,
  ]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
  tags = {
    Name        = "${var.stack_name}-api-gateway-deployment"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.stack_name}-api-gateway-usage-plan"
  description = "Usage plan for ${var.application_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_deployment.this.stage_name
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
    Name        = "${var.stack_name}-api-gateway-usage-plan"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "add_item.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tags = {
    Name        = "${var.stack_name}-lambda-add-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "get_item.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tags = {
    Name        = "${var.stack_name}-lambda-get-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "get_all_items.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tags = {
    Name        = "${var.stack_name}-lambda-get-all-items"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "put_item" {
  filename      = "put_item.zip"
  function_name = "${var.stack_name}-put-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tags = {
    Name        = "${var.stack_name}-lambda-put-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "post_done_item" {
  filename      = "post_done_item.zip"
  function_name = "${var.stack_name}-post-done-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tags = {
    Name        = "${var.stack_name}-lambda-post-done-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "delete_item.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  tags = {
    Name        = "${var.stack_name}-lambda-delete-item"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.stack_name}-amplify-app"
  description = "Amplify app for ${var.application_name}"
  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
  tags = {
    Name        = "${var.stack_name}-amplify-branch"
    Environment = "prod"
    Project     = var.application_name
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec"
  description = "API Gateway execution role for ${var.application_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-api-gateway-exec"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec-policy"
  description = "API Gateway execution policy for ${var.application_name}"
  policy      = jsonencode({
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
    ]
  })
  tags = {
    Name        = "${var.stack_name}-api-gateway-exec-policy"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec"
  description = "Lambda execution role for ${var.application_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-lambda-exec"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec-policy"
  description = "Lambda execution policy for ${var.application_name}"
  policy      = jsonencode({
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
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-lambda-exec-policy"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.stack_name}-amplify-exec"
  description = "Amplify execution role for ${var.application_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-amplify-exec"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "amplify_exec" {
  name        = "${var.stack_name}-amplify-exec-policy"
  description = "Amplify execution policy for ${var.application_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-amplify-exec-policy"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

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

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.this.stage_name
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.put_item.function_name,
    aws_lambda_function.post_done_item.function_name,
    aws_lambda_function.delete_item.function_name,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.this.branch_name
}
