# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "todo-app-user-pool"
  alias_attributes    = ["email"]
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]
  email_configuration {
    email_sending_account = "DEVELOPER"
  }
  policies {
    password_policy {
      minimum_length    = 6
      require_uppercase = true
      require_lowercase = true
    }
  }
  tags = {
    Name        = "Todo App User Pool"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "todo-app-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "todo-app"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "dynamodb_table" {
  name           = "todo-table-${aws_cognito_user_pool.user_pool.name}"
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
    Name        = "Todo Table"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "todo-api"
  description = "Todo API"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name          = "cognito-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
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
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
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

resource "aws_api_gateway_stage" "prod_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  deployment_id = aws_api_gateway_deployment.deployment.id
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  depends_on  = [aws_api_gateway_integration.post_integration, aws_api_gateway_integration.get_integration, aws_api_gateway_integration.put_integration, aws_api_gateway_integration.delete_integration]
}

# Lambda Functions
resource "aws_lambda_function" "post_function" {
  filename      = "lambda_function_post_payload.zip"
  function_name = "todo-post-function"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.dynamodb_table.name
    }
  }
  tags = {
    Name        = "Todo Post Function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "get_function" {
  filename      = "lambda_function_get_payload.zip"
  function_name = "todo-get-function"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.dynamodb_table.name
    }
  }
  tags = {
    Name        = "Todo Get Function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "put_function" {
  filename      = "lambda_function_put_payload.zip"
  function_name = "todo-put-function"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.dynamodb_table.name
    }
  }
  tags = {
    Name        = "Todo Put Function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

resource "aws_lambda_function" "delete_function" {
  filename      = "lambda_function_delete_payload.zip"
  function_name = "todo-delete-function"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 60
  memory_size   = 1024
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.dynamodb_table.name
    }
  }
  tags = {
    Name        = "Todo Delete Function"
    Environment = "prod"
    Project     = "todo-app"
  }
}

# API Gateway Integrations
resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.api_gateway.region}:${aws_api_gateway_rest_api.api_gateway.account_id}:function:todo-post-function/invocations"
}

resource "aws_api_gateway_integration" "get_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.api_gateway.region}:${aws_api_gateway_rest_api.api_gateway.account_id}:function:todo-get-function/invocations"
}

resource "aws_api_gateway_integration" "put_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.put_method.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.api_gateway.region}:${aws_api_gateway_rest_api.api_gateway.account_id}:function:todo-put-function/invocations"
}

resource "aws_api_gateway_integration" "delete_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.delete_method.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.api_gateway.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.api_gateway.region}:${aws_api_gateway_rest_api.api_gateway.account_id}:function:todo-delete-function/invocations"
}

# Lambda Permissions
resource "aws_lambda_permission" "post_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "put_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.put_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "delete_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = "todo-amplify-app"
  description = "Todo Amplify App"
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

resource "aws_amplify_backend_environment" "amplify_backend_environment" {
  app_id      = aws_amplify_app.amplify_app.id
  environment = "prod"
}

# IAM Roles
resource "aws_iam_role" "lambda_exec" {
  name        = "todo-lambda-exec"
  description = "Todo Lambda Execution Role"

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

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "todo-lambda-policy"
  description = "Todo Lambda Policy"

  policy = jsonencode({
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
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.dynamodb_table.arn
      }
    ]
  })
}

resource "aws_iam_role" "apigateway_exec" {
  name        = "todo-apigateway-exec"
  description = "Todo API Gateway Execution Role"

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

resource "aws_iam_role_policy_attachment" "apigateway_policy" {
  role       = aws_iam_role.apigateway_exec.name
  policy_arn = aws_iam_policy.apigateway_policy.arn
}

resource "aws_iam_policy" "apigateway_policy" {
  name        = "todo-apigateway-policy"
  description = "Todo API Gateway Policy"

  policy = jsonencode({
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

resource "aws_iam_role" "amplify_exec" {
  name        = "todo-amplify-exec"
  description = "Todo Amplify Execution Role"

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
}

resource "aws_iam_role_policy_attachment" "amplify_policy" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "todo-amplify-policy"
  description = "Todo Amplify Policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:GetBackendEnvironment"
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.amplify_app.arn
      }
    ]
  })
}

# Outputs
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.dynamodb_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "lambda_function_name_post" {
  value = aws_lambda_function.post_function.function_name
}

output "lambda_function_name_get" {
  value = aws_lambda_function.get_function.function_name
}

output "lambda_function_name_put" {
  value = aws_lambda_function.put_function.function_name
}

output "lambda_function_name_delete" {
  value = aws_lambda_function.delete_function.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_id" {
  value = aws_amplify_branch.amplify_branch.id
}
