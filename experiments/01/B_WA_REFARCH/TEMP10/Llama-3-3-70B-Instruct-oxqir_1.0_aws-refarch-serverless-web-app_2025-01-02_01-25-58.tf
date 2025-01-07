provider "aws" {
  region = "us-west-2"
}

variable "application_name" {
  default = "my-serverless-web-app"
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
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.application_name}-user-pool"
  email_verification  = true
  email_configuration = {
    reply_to_email_address = "noreply@example.com"
  }
  password_policy = {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  schema = [
    {
      name                = "email"
      required            = true
      data_type           = "Email"
      attribute_data_type = "String"
      developer_only_attribute = false
    }
  ]
  alias_attributes = ["email"]
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.application_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain = "${var.application_name}.${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name         = "${var.application_name}-todo-table-${var.stack_name}"
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
}

# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.application_name}-api-gateway"
  description = "API Gateway for ${var.application_name}"
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "put_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "delete_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name           = "CognitoAuthorizer"
  type           = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
}

resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on  = [aws_api_gateway_method.post_item_method, aws_api_gateway_method.get_item_method, aws_api_gateway_method.put_item_method, aws_api_gateway_method.delete_item_method]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.application_name}-usage-plan"
  description = "Usage plan for ${var.application_name}"
}

resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
  key_type       = "API_KEY"
}

# Lambda Functions
resource "aws_lambda_function" "add_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-add-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "get_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-get-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "put_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-put-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "delete_item_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-delete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

# Lambda Permissions
resource "aws_lambda_permission" "apigateway_add_item_permission" {
  statement_id  = "AllowAPIGatewayToAddItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_get_item_permission" {
  statement_id  = "AllowAPIGatewayToGetItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_item_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_put_item_permission" {
  statement_id  = "AllowAPIGatewayToPutItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.put_item_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigateway_delete_item_permission" {
  statement_id  = "AllowAPIGatewayToDeleteItem"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.delete_item_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api_gateway.execution_arn}/*/*"
}

# Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = "${var.application_name}-amplify-app"
  description = "Amplify app for ${var.application_name}"
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = var.github_branch
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.application_name}-lambda-exec-role"
  description = "Lambda execution role for ${var.application_name}"

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

resource "aws_iam_policy" "lambda_exec_policy" {
  name        = "${var.application_name}-lambda-exec-policy"
  description = "Lambda execution policy for ${var.application_name}"

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
      "Resource": "${aws_dynamodb_table.todo_table.arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_exec_policy.arn
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.application_name}-api-gateway-role"
  description = "API Gateway role for ${var.application_name}"

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

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.application_name}-api-gateway-policy"
  description = "API Gateway policy for ${var.application_name}"

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

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.application_name}-amplify-role"
  description = "Amplify role for ${var.application_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "amplify.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.application_name}-amplify-policy"
  description = "Amplify policy for ${var.application_name}"

  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "amplify:CreateApp",
        "amplify:CreateBranch",
        "amplify:CreateDeployment",
        "amplify:CreateJob",
        "amplify:CreateWebhook"
      ],
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "custom_domain" {
  value = aws_cognito_user_pool_domain.user_pool_domain.domain
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

output "lambda_function_names" {
  value = [
    aws_lambda_function.add_item_lambda.function_name,
    aws_lambda_function.get_item_lambda.function_name,
    aws_lambda_function.put_item_lambda.function_name,
    aws_lambda_function.delete_item_lambda.function_name,
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.amplify_branch.branch_name
}
