provider "aws" {
  region = "us-west-2"
}

variable "project_name" {
  default = "my-project"
}

variable "environment" {
  default = "prod"
}

variable "stack_name" {
  default = "my-stack"
}

variable "github_repository" {
  default = "https://github.com/user/repository"
}

variable "github_branch" {
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.project_name}-${var.environment}-user-pool"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.project_name}-${var.environment}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.project_name}-${var.environment}"
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
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.project_name}-${var.environment}-api"
  description = "API for ${var.project_name}"
}

resource "aws_api_gateway_authorizer" "this" {
  name        = "cognito-authorizer"
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
  rest_api_id = aws_api_gateway_rest_api.this.id
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
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "get_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_method.post_item,
    aws_api_gateway_method.get_item,
    aws_api_gateway_method.get_items,
    aws_api_gateway_method.put_item,
    aws_api_gateway_method.delete_item,
  ]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.project_name}-${var.environment}-usage-plan"
  description = "Usage plan for ${var.project_name}"
}

resource "aws_api_gateway_usage_plan_key" "this" {
  usage_plan_id = aws_api_gateway_usage_plan.this.id
  key_type      = "API_KEY"
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda-functions/add-item.zip"
  function_name = "${var.project_name}-${var.environment}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda-functions/get-item.zip"
  function_name = "${var.project_name}-${var.environment}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "get_items" {
  filename      = "lambda-functions/get-items.zip"
  function_name = "${var.project_name}-${var.environment}-get-items"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "put_item" {
  filename      = "lambda-functions/put-item.zip"
  function_name = "${var.project_name}-${var.environment}-put-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda-functions/delete-item.zip"
  function_name = "${var.project_name}-${var.environment}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

# API Gateway Integration
resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_items.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_items.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.put_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.project_name}-${var.environment}"
  description = "Amplify app for ${var.project_name}"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment = var.environment
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec" {
  name        = "${var.project_name}-${var.environment}-lambda-exec"
  description = "Execution role for Lambda functions"
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

resource "aws_iam_policy" "lambda_exec" {
  name        = "${var.project_name}-${var.environment}-lambda-exec-policy"
  description = "Execution policy for Lambda functions"
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
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:log-group:/aws/lambda/${var.project_name}-${var.environment}-*"
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

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.project_name}-${var.environment}-api-gateway-exec"
  description = "Execution role for API Gateway"
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

resource "aws_iam_policy" "api_gateway_exec" {
  name        = "${var.project_name}-${var.environment}-api-gateway-exec-policy"
  description = "Execution policy for API Gateway"
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
        Resource = "arn:aws:logs:${aws_api_gateway_rest_api.this.region}:${aws_api_gateway_rest_api.this.account_id}:log-group:/aws/apigateway/${var.project_name}-${var.environment}"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.project_name}-${var.environment}-amplify-exec"
  description = "Execution role for Amplify"
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

resource "aws_iam_policy" "amplify_exec" {
  name        = "${var.project_name}-${var.environment}-amplify-exec-policy"
  description = "Execution policy for Amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateEnvironment",
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.this.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

# Outputs
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

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.this.branch_name
}

output "lambda_function_name" {
  value = aws_lambda_function.add_item.function_name
}
