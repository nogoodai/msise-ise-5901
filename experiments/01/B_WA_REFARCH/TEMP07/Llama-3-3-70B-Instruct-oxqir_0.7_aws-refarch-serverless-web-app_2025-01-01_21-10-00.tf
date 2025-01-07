provider "aws" {
  region = "us-east-1"
}

variable "application_name" {
  default = "todo-app"
}

variable "stack_name" {
  default = "prod"
}

variable "github_repo" {
  default = "https://github.com/user/todo-app"
}

variable "github_branch" {
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.application_name}-${var.stack_name}-user-pool"
  email_configuration = {
    email_verification_message = "Your verification code is {####}."
    email_verification_subject = "Your verification code"
  }
  username_attributes = ["email"]
  alias_attributes     = ["email"]
  auto_verified_attributes = ["email"]
  password_policy = {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls        = ["https://${var.application_name}-${var.stack_name}.auth.us-east-1.amazoncognito.com/oauth2/idpresponse"]
  logout_urls           = ["https://${var.application_name}-${var.stack_name}.auth.us-east-1.amazoncognito.com/logout"]
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.application_name}-${var.stack_name}"
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
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API for ${var.application_name}"
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "this" {
  name          = "${var.application_name}-${var.stack_name}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id   = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_resource" "item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_resource" "item_id" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.item.id
  path_part   = "{id}"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "get_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = aws_api_gateway_method.get_items.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.get_items.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.post_item_done.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.item_id.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_integration.post_item,
    aws_api_gateway_integration.get_item,
    aws_api_gateway_integration.get_items,
    aws_api_gateway_integration.put_item,
    aws_api_gateway_integration.post_item_done,
    aws_api_gateway_integration.delete_item
  ]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = var.stack_name
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.application_name}-${var.stack_name}-usage-plan"
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
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-get-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-get-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-get-items"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-update-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-complete-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-delete-item"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.application_name}-${var.stack_name}"
  description = "Amplify app for ${var.application_name}"
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

resource "aws_amplify_app_version" "this" {
  app_id     = aws_amplify_app.this.id
  source_url = var.github_repo
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway"
  description = "API Gateway role for ${var.application_name}"
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
    Name        = "${var.application_name}-${var.stack_name}-api-gateway"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "api_gateway" {
  name        = "${var.application_name}-${var.stack_name}-api-gateway"
  description = "API Gateway policy for ${var.application_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

resource "aws_iam_role" "amplify" {
  name        = "${var.application_name}-${var.stack_name}-amplify"
  description = "Amplify role for ${var.application_name}"
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
    Name        = "${var.application_name}-${var.stack_name}-amplify"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "amplify" {
  name        = "${var.application_name}-${var.stack_name}-amplify"
  description = "Amplify policy for ${var.application_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:CreateBranch",
          "amplify:UpdateBranch",
          "amplify:DeleteBranch"
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.this.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

resource "aws_iam_role" "lambda" {
  name        = "${var.application_name}-${var.stack_name}-lambda"
  description = "Lambda role for ${var.application_name}"
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
    Name        = "${var.application_name}-${var.stack_name}-lambda"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda" {
  name        = "${var.application_name}-${var.stack_name}-lambda"
  description = "Lambda policy for ${var.application_name}"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
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

output "lambda_function_name" {
  value = aws_lambda_function.add_item.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
