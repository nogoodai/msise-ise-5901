# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Create Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "todo-pool-${var.stack_name}"
  username_attributes = ["email"]
  auto_verified_attributes = [
    "email",
  ]
  alias_attributes = [
    "email",
  ]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
  tags = {
    Name        = "todo-cognito-pool-${var.stack_name}"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name            = "todo-client-${var.stack_name}"
  user_pool_id    = aws_cognito_user_pool.this.id
  generate_secret = false
  supported_identity_providers = [
    "COGNITO",
  ]
  callback_urls   = [
    "https://example.com/callback",
  ]
  allowed_oauth_flows         = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = [
    "email",
    "phone",
    "openid",
  ]
  allowed_oauth_authorize_scopes = [
    "email",
    "phone",
    "openid",
  ]
}

# Create Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "todo-domain-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# Create DynamoDB Table
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
    },
  ]
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "todo-dynamodb-table-${var.stack_name}"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Create API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "todo-api-${var.stack_name}"
  description = "Todo API"
}

# Create API Gateway Resource
resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

# Create API Gateway Method for GET /item
resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

# Create API Gateway Method for POST /item
resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

# Create API Gateway Method for GET /item/{id}
resource "aws_api_gateway_method" "get_item_by_id" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  request_parameters = {
    "method.request.path.id" = true
  }
}

# Create API Gateway Method for PUT /item/{id}
resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  request_parameters = {
    "method.request.path.id" = true
  }
}

# Create API Gateway Method for POST /item/{id}/done
resource "aws_api_gateway_method" "post_item_done" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  request_parameters = {
    "method.request.path.id" = true
  }
}

# Create API Gateway Method for DELETE /item/{id}
resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
  request_parameters = {
    "method.request.path.id" = true
  }
}

# Create API Gateway Authorizer
resource "aws_api_gateway_authorizer" "this" {
  name          = "todo-authorizer-${var.stack_name}"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

# Create Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda-function.zip"
  function_name = "todo-add-item-${var.stack_name}"
  handler       = "index.add_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_execution.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda-function.zip"
  function_name = "todo-get-item-${var.stack_name}"
  handler       = "index.get_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_execution.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "get_items" {
  filename      = "lambda-function.zip"
  function_name = "todo-get-items-${var.stack_name}"
  handler       = "index.get_items"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_execution.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda-function.zip"
  function_name = "todo-update-item-${var.stack_name}"
  handler       = "index.update_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_execution.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda-function.zip"
  function_name = "todo-complete-item-${var.stack_name}"
  handler       = "index.complete_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_execution.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda-function.zip"
  function_name = "todo-delete-item-${var.stack_name}"
  handler       = "index.delete_item"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_execution.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

# Create API Gateway Integration with Lambda Functions
resource "aws_api_gateway_integration" "add_item" {
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

resource "aws_api_gateway_integration" "get_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_items.arn}/invocations"
}

resource "aws_api_gateway_integration" "update_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "complete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item_done.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

# Create API Gateway Deployment
resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_integration.add_item,
    aws_api_gateway_integration.get_item,
    aws_api_gateway_integration.get_items,
    aws_api_gateway_integration.update_item,
    aws_api_gateway_integration.complete_item,
    aws_api_gateway_integration.delete_item,
  ]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# Create API Gateway Stage
resource "aws_api_gateway_stage" "this" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
}

# Create API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "this" {
  name         = "todo-usage-plan-${var.stack_name}"
  description  = "Todo usage plan"
  product_code = "TODO-SERVICE"
}

# Create API Gateway Usage Plan Key
resource "aws_api_gateway_usage_plan_key" "this" {
  usage_plan_id = aws_api_gateway_usage_plan.this.id
  key_type      = "API_KEY"
  key_id        = aws_api_gateway_api_key.this.id
}

# Create API Gateway API Key
resource "aws_api_gateway_api_key" "this" {
  name        = "todo-api-key-${var.stack_name}"
  description = "Todo API key"
}

# Create Amplify App
resource "aws_amplify_app" "this" {
  name        = "todo-app-${var.stack_name}"
  description = "Todo app"
}

# Create Amplify Branch
resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
}

# Create IAM Roles and Policies
resource "aws_iam_role" "lambda_execution" {
  name        = "todo-lambda-execution-${var.stack_name}"
  description = "Todo lambda execution role"
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
}

resource "aws_iam_policy" "lambda_execution" {
  name        = "todo-lambda-execution-policy-${var.stack_name}"
  description = "Todo lambda execution policy"
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
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_execution.arn
}

resource "aws_iam_role" "api_gateway_execution" {
  name        = "todo-api-gateway-execution-${var.stack_name}"
  description = "Todo API Gateway execution role"
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
}

resource "aws_iam_policy" "api_gateway_execution" {
  name        = "todo-api-gateway-execution-policy-${var.stack_name}"
  description = "Todo API Gateway execution policy"
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
}

resource "aws_iam_role_policy_attachment" "api_gateway_execution" {
  role       = aws_iam_role.api_gateway_execution.name
  policy_arn = aws_iam_policy.api_gateway_execution.arn
}

resource "aws_iam_role" "amplify_execution" {
  name        = "todo-amplify-execution-${var.stack_name}"
  description = "Todo Amplify execution role"
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
}

resource "aws_iam_policy" "amplify_execution" {
  name        = "todo-amplify-execution-policy-${var.stack_name}"
  description = "Todo Amplify execution policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:ListApps",
          "amplify:ListBranches",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_execution" {
  role       = aws_iam_role.amplify_execution.name
  policy_arn = aws_iam_policy.amplify_execution.arn
}

variable "stack_name" {
  type = string
  default = "todo-stack"
}

variable "aws_region" {
  type = string
  default = "us-west-2"
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
  value = aws_api_gateway_stage.this.stage_name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.this.branch_name
}
