# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Create Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "todo-pool"
  email_username      = true
  email_verification  = true
  alias_attributes   = ["email"]
  username_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name         = "todo-client"
  user_pool_id = aws_cognito_user_pool.this.id
  generate_secret = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls = ["https://example.com/callback"]
}

# Create Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "todo-{aws_cognito_user_pool.this.name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name         = "todo-table"
  billing_mode = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  hash_key       = "cognito-username"
  range_key      = "id"
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  server_side_encryption {
    enabled     = true
  }
}

# Create API Gateway Rest API
resource "aws_api_gateway_rest_api" "this" {
  name        = "todo-api"
  description = "This is the API for the Todo application"
}

# Create API Gateway Resource and Method for Add Item
resource "aws_api_gateway_resource" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.add_item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

# Create API Gateway Resource and Method for Get Item
resource "aws_api_gateway_resource" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.add_item.id
  path_part   = "{id}"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.get_item.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

# Create API Gateway Resource and Method for Get All Items
resource "aws_api_gateway_method" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.add_item.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

# Create API Gateway Resource and Method for Update Item
resource "aws_api_gateway_method" "update_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.get_item.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

# Create API Gateway Resource and Method for Complete Item
resource "aws_api_gateway_resource" "complete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.get_item.id
  path_part   = "done"
}

resource "aws_api_gateway_method" "complete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.complete_item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

# Create API Gateway Resource and Method for Delete Item
resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.get_item.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

# Create API Gateway Deployment
resource "aws_api_gateway_deployment" "this" {
  depends_on  = [aws_api_gateway_method.add_item, aws_api_gateway_method.get_item, aws_api_gateway_method.get_all_items, aws_api_gateway_method.update_item, aws_api_gateway_method.complete_item, aws_api_gateway_method.delete_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# Create API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "todo-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.this.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

# Create Lambda Function for Add Item
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
}

# Create Lambda Function for Get Item
resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
}

# Create Lambda Function for Get All Items
resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
}

# Create Lambda Function for Update Item
resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
}

# Create Lambda Function for Complete Item
resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
}

# Create Lambda Function for Delete Item
resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "todo-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
}

# Create API Gateway Integration with Lambda Function for Add Item
resource "aws_api_gateway_integration" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.add_item.id
  http_method = aws_api_gateway_method.add_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

# Create API Gateway Integration with Lambda Function for Get Item
resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.get_item.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

# Create API Gateway Integration with Lambda Function for Get All Items
resource "aws_api_gateway_integration" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.add_item.id
  http_method = aws_api_gateway_method.get_all_items.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_all_items.arn}/invocations"
}

# Create API Gateway Integration with Lambda Function for Update Item
resource "aws_api_gateway_integration" "update_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.get_item.id
  http_method = aws_api_gateway_method.update_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

# Create API Gateway Integration with Lambda Function for Complete Item
resource "aws_api_gateway_integration" "complete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.complete_item.id
  http_method = aws_api_gateway_method.complete_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item.arn}/invocations"
}

# Create API Gateway Integration with Lambda Function for Delete Item
resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.get_item.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

# Create IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec" {
  name        = "todo-lambda-exec"
  description = "Execution role for Todo Lambda functions"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Create IAM Policy for Lambda Execution
resource "aws_iam_policy" "lambda_exec" {
  name        = "todo-lambda-exec-policy"
  description = "Policy for Todo Lambda functions"

  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "${aws_dynamodb_table.this.arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

# Attach IAM Policy to IAM Role for Lambda Execution
resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

# Create IAM Role for API Gateway Execution
resource "aws_iam_role" "api_gateway_exec" {
  name        = "todo-api-gateway-exec"
  description = "Execution role for Todo API Gateway"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Create IAM Policy for API Gateway Execution
resource "aws_iam_policy" "api_gateway_exec" {
  name        = "todo-api-gateway-exec-policy"
  description = "Policy for Todo API Gateway"

  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

# Attach IAM Policy to IAM Role for API Gateway Execution
resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

# Create Amplify App
resource "aws_amplify_app" "this" {
  name        = "todo-app"
  description = "This is the Todo app"
}

# Create Amplify Branch
resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
}

# Create Amplify Environment
resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment = "prod"
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${aws_region}.amazonaws.com/prod"
}

output "amplify_app_url" {
  value = "https://${aws_amplify_app.this.name}.amplify.app"
}
