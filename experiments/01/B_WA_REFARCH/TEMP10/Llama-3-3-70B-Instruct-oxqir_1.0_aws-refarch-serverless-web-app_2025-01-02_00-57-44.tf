provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "application_name" {
  type    = string
  default = "serverless-web-app"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "github_repository" {
  type    = string
  default = "https://github.com/username/repository"
}

variable "github_token" {
  type = string
  sensitive = true
}

variable "sst_name" {
  type = string
  default = "serverless-web-app-stack"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.sst_name}-user-pool"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  email_verification_subject = "Your verification code"
  username_configuration {
    case_sensitive = false
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "${var.sst_name}-user-pool"
    Environment = var.environment
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.sst_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls = ["https://example.com"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "custom_domain" {
  domain       = "${var.application_name}.${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "${var.sst_name}-todo-table"
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
  tags = {
    Name        = "${var.sst_name}-todo-table"
    Environment = var.environment
    Project     = var.application_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.sst_name}-api-gateway"
  description = "Serverless Web App API Gateway"
  tags = {
    Name        = "${var.sst_name}-api-gateway"
    Environment = var.environment
    Project     = var.application_name
  }
}

# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "authorizer" {
  name           = "${var.sst_name}-authorizer"
  rest_api_id    = aws_api_gateway_rest_api.api_gateway.id
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# API Gateway Resource and Method
resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "put_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "delete_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_method.get_method, aws_api_gateway_method.post_method, aws_api_gateway_method.put_method, aws_api_gateway_method.delete_method]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "usage_plan" {
  name         = "${var.sst_name}-usage-plan"
  description  = "Serverless Web App Usage Plan"
  api_keys     = []
  product_code = null
  tags = {
    Name        = "${var.sst_name}-usage-plan"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
  key_type       = "API_KEY"
  key_id         = null
}

resource "aws_api_gateway_quota" "quota" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  limit       = 5000
  offset      = 0
  period      = "DAY"
}

resource "aws_api_gateway_usage_plan_key" "burst_limit" {
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
  key_type       = "API_KEY"
  key_id         = null
}

resource "aws_api_gateway_quota" "burst_quota" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  limit       = 100
  offset      = 0
  period      = "SECOND"
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.sst_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_execution_role.arn
  tags = {
    Name        = "${var.sst_name}-add-item"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.sst_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_execution_role.arn
  tags = {
    Name        = "${var.sst_name}-get-item"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.sst_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_execution_role.arn
  tags = {
    Name        = "${var.sst_name}-get-all-items"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.sst_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_execution_role.arn
  tags = {
    Name        = "${var.sst_name}-update-item"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.sst_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_execution_role.arn
  tags = {
    Name        = "${var.sst_name}-complete-item"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.sst_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_execution_role.arn
  tags = {
    Name        = "${var.sst_name}-delete-item"
    Environment = var.environment
    Project     = var.application_name
  }
}

# Lambda Permissions
resource "aws_lambda_permission" "apigateway_add_item" {
  statement_id  = "AllowExecutionFromAPIGatewayAddItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_get_item" {
  statement_id  = "AllowExecutionFromAPIGatewayGetItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_get_all_items" {
  statement_id  = "AllowExecutionFromAPIGatewayGetAllItems"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_all_items.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_update_item" {
  statement_id  = "AllowExecutionFromAPIGatewayUpdateItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.update_item.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_complete_item" {
  statement_id  = "AllowExecutionFromAPIGatewayCompleteItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.complete_item.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_delete_item" {
  statement_id  = "AllowExecutionFromAPIGatewayDeleteItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_item.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = var.application_name
  description = "Serverless Web App Amplify App"
  tags = {
    Name        = var.application_name
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_execution_role" {
  name        = "${var.sst_name}-lambda-execution-role"
  description = "Serverless Web App Lambda Execution Role"
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
    Name        = "${var.sst_name}-lambda-execution-role"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_execution_policy" {
  name        = "${var.sst_name}-lambda-execution-policy"
  description = "Serverless Web App Lambda Execution Policy"
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
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetServiceGraph",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
  tags = {
    Name        = "${var.sst_name}-lambda-execution-policy"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_execution_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

resource "aws_iam_role" "apigateway_execution_role" {
  name        = "${var.sst_name}-apigateway-execution-role"
  description = "Serverless Web App API Gateway Execution Role"
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
    Name        = "${var.sst_name}-apigateway-execution-role"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "apigateway_execution_policy" {
  name        = "${var.sst_name}-apigateway-execution-policy"
  description = "Serverless Web App API Gateway Execution Policy"
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
    Name        = "${var.sst_name}-apigateway-execution-policy"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "apigateway_execution_policy_attachment" {
  role       = aws_iam_role.apigateway_execution_role.name
  policy_arn = aws_iam_policy.apigateway_execution_policy.arn
}

resource "aws_iam_role" "amplify_execution_role" {
  name        = "${var.sst_name}-amplify-execution-role"
  description = "Serverless Web App Amplify Execution Role"
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
    Name        = "${var.sst_name}-amplify-execution-role"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "amplify_execution_policy" {
  name        = "${var.sst_name}-amplify-execution-policy"
  description = "Serverless Web App Amplify Execution Policy"
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
    Name        = "${var.sst_name}-amplify-execution-policy"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_execution_policy_attachment" {
  role       = aws_iam_role.amplify_execution_role.name
  policy_arn = aws_iam_policy.amplify_execution_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_execution_arn" {
  value = aws_api_gateway_rest_api.api_gateway.execution_arn
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
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
}
