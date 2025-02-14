provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type = string
  default = "todo-app"
}

variable "cognito_user_pool_name" {
  type = string
  default = "todo-app-user-pool"
}

variable "cognito_user_pool_client_name" {
  type = string
  default = "todo-app-client"
}

variable "dynamodb_table_name" {
  type = string
  default = "todo-table-${var.stack_name}"
}

variable "api_gateway_name" {
  type = string
  default = "todo-app-api-gateway"
}

variable "lambda_function_name" {
  type = string
  default = "todo-app-lambda"
}

variable "amplify_app_name" {
  type = string
  default = "todo-app-amplify"
}

variable "github_repository" {
  type = string
  default = "https://github.com/user/todo-app-frontend.git"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name = var.cognito_user_pool_name
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols = false
    require_numbers = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name = var.cognito_user_pool_client_name
  user_pool_id = aws_cognito_user_pool.this.id
  generate_secret = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name = var.dynamodb_table_name
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
      key_type = "HASH"
    },
    {
      attribute_name = "id"
      key_type = "RANGE"
    }
  ]
  billing_mode = "PROVISIONED"
  read_capacity_units = 5
  write_capacity_units = 5
  server_side_encryption {
    enabled = true
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name = var.api_gateway_name
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id = aws_api_gateway_rest_api.this.root_resource_id
  path_part = "item"
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

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.lambda_function_name}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.lambda_function_name}/invocations"
}

resource "aws_api_gateway_integration" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.lambda_function_name}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type = "LAMBDA"
  uri = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:${var.lambda_function_name}/invocations"
}

resource "aws_api_gateway_authorizer" "this" {
  name = "CognitoAuthorizer"
  rest_api_id = aws_api_gateway_rest_api.this.id
  type = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.post_item, aws_api_gateway_integration.get_item, aws_api_gateway_integration.put_item, aws_api_gateway_integration.delete_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name = "TodoAppUsagePlan"
  description = "Usage plan for Todo App API"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage = aws_api_gateway_deployment.this.stage_name
  }
  quota {
    limit = 5000
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit = 50
  }
}

# Lambda Function
resource "aws_lambda_function" "this" {
  filename = "lambda_function_payload.zip"
  function_name = var.lambda_function_name
  handler = "index.handler"
  runtime = "nodejs12.x"
  role = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
    }
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name = "ApiGatewayExecRole"
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
}

resource "aws_iam_policy" "api_gateway_exec" {
  name = "ApiGatewayExecPolicy"
  description = "Policy for API Gateway execution role"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "logs:CreateLogGroup"
        Effect = "Allow"
        Resource = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/apigateway/${var.api_gateway_name}"
      },
      {
        Action = "logs:CreateLogStream"
        Effect = "Allow"
        Resource = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/apigateway/${var.api_gateway_name}"
      },
      {
        Action = "logs:PutLogEvents"
        Effect = "Allow"
        Resource = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/apigateway/${var.api_gateway_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name = "LambdaExecRole"
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
}

resource "aws_iam_policy" "lambda_exec" {
  name = "LambdaExecPolicy"
  description = "Policy for Lambda execution role"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "logs:CreateLogGroup"
        Effect = "Allow"
        Resource = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/lambda/${var.lambda_function_name}"
      },
      {
        Action = "logs:CreateLogStream"
        Effect = "Allow"
        Resource = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/lambda/${var.lambda_function_name}"
      },
      {
        Action = "logs:PutLogEvents"
        Effect = "Allow"
        Resource = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/lambda/${var.lambda_function_name}"
      },
      {
        Action = "dynamodb:GetItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = "dynamodb:PutItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = "dynamodb:UpdateItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = "dynamodb:DeleteItem"
        Effect = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = "xray:PutTraceSegments"
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = "xray:PutTelemetryRecords"
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = "xray:GetServiceGraph"
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = "cloudwatch:PutMetricData"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

# Amplify App
resource "aws_amplify_app" "this" {
  name = var.amplify_app_name
  description = "Todo App Amplify App"
  platform = "WEB"
  environment {
    name = "master"
    stage = "PRODUCTION"
  }
  custom_rule {
    source = "/"
    target = "/index.html"
    status = "200"
  }
}

resource "aws_amplify_branch" "this" {
  app_id = aws_amplify_app.this.id
  branch_name = "master"
  stage = "PRODUCTION"
}

resource "aws_amplify_environment" "this" {
  app_id = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  name = "master"
}

resource "aws_amplify_deployment" "this" {
  app_id = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  environment_name = aws_amplify_environment.this.name
  source {
    code_commit {
      repository = var.github_repository
      branch = "master"
    }
    build_spec = "buildspec.yml"
  }
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
  value = aws_lambda_function.this.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.this.branch_name
}
