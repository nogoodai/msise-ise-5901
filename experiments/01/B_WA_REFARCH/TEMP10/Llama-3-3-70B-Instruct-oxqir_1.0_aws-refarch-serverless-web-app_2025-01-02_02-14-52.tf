# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
  required_version = ">= 1.4.5"
}

# Configure provider with default credentials and region
provider "aws" {
  region = "us-west-2"
}

# Set up variables
variable "project_name" {
  default = "serverless-web-app"
  description = "Name of the project"
}

variable "stack_name" {
  default = "main-stack"
  description = "Name of the stack"
}

variable "github_repo" {
  default = "github-repo-url"
  description = "URL of the GitHub repository"
}

# Create Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.project_name}-${var.stack_name}-user-pool"
  username_attributes = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_configuration {
    email_sending_account = "DEVELOPER"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.project_name}-${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Create Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain               = "${var.project_name}-${var.stack_name}"
  user_pool_id         = aws_cognito_user_pool.user_pool.id
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name         = "${var.project_name}-${var.stack_name}-todo-table"
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

# Create API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.project_name}-${var.stack_name}-api-gateway"
  description = "API Gateway for ${var.project_name}"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name        = "${var.project_name}-${var.stack_name}-cognito-authorizer"
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

# Create API Gateway Resources and Methods
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

resource "aws_api_gateway_method" "get_all_items_method" {
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

resource "aws_api_gateway_method" "post_done_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
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

# Create Lambda Functions
resource "aws_lambda_function" "add_item_function" {
  filename      = "lambda_functions/add_item_function.zip"
  function_name = "${var.project_name}-${var.stack_name}-add-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "lambda_functions/get_item_function.zip"
  function_name = "${var.project_name}-${var.stack_name}-get-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
}

resource "aws_lambda_function" "get_all_items_function" {
  filename      = "lambda_functions/get_all_items_function.zip"
  function_name = "${var.project_name}-${var.stack_name}-get-all-items-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
}

resource "aws_lambda_function" "update_item_function" {
  filename      = "lambda_functions/update_item_function.zip"
  function_name = "${var.project_name}-${var.stack_name}-update-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
}

resource "aws_lambda_function" "complete_item_function" {
  filename      = "lambda_functions/complete_item_function.zip"
  function_name = "${var.project_name}-${var.stack_name}-complete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
}

resource "aws_lambda_function" "delete_item_function" {
  filename      = "lambda_functions/delete_item_function.zip"
  function_name = "${var.project_name}-${var.stack_name}-delete-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
}

# Create API Gateway Integrations
resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.post_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item_function.arn}/invocations"
  depends_on  = [aws_lambda_function.add_item_function]
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item_function.arn}/invocations"
  depends_on  = [aws_lambda_function.get_item_function]
}

resource "aws_api_gateway_integration" "get_all_items_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.get_all_items_method.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_all_items_function.arn}/invocations"
  depends_on  = [aws_lambda_function.get_all_items_function]
}

resource "aws_api_gateway_integration" "put_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.put_item_method.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item_function.arn}/invocations"
  depends_on  = [aws_lambda_function.update_item_function]
}

resource "aws_api_gateway_integration" "post_done_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.post_done_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item_function.arn}/invocations"
  depends_on  = [aws_lambda_function.complete_item_function]
}

resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.delete_item_method.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item_function.arn}/invocations"
  depends_on  = [aws_lambda_function.delete_item_function]
}

# Create Amplify App
resource "aws_amplify_app" "amplify_app" {
  name        = "${var.project_name}-${var.stack_name}"
  description = "Amplify App for ${var.project_name}"
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = "master"
}

resource "aws_amplify_environment" "amplify_environment" {
  app_id      = aws_amplify_app.amplify_app.id
  branch_name = aws_amplify_branch.amplify_branch.branch_name
  environment_variables = {
    API_URL = "https://${aws_api_gateway_rest_api.api_gateway.id}.execute-api.${aws_region}.amazonaws.com/${aws_api_gateway_deployment.api_gateway_deployment.stage_name}"
  }
}

# Create IAM Roles and Policies
resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.project_name}-${var.stack_name}-api-gateway-role"
  description = "IAM Role for API Gateway"
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
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.project_name}-${var.stack_name}-api-gateway-policy"
  description = "IAM Policy for API Gateway"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:${aws_region}:${aws_account_id}:*"
        Effect    = "Allow"
      },
      {
        Action = "logs:CreateLogStream"
        Resource = "arn:aws:logs:${aws_region}:${aws_account_id}:*"
        Effect    = "Allow"
      },
      {
        Action = "logs:PutLogEvents"
        Resource = "arn:aws:logs:${aws_region}:${aws_account_id}:*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_role_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "lambda_role" {
  name        = "${var.project_name}-${var.stack_name}-lambda-role"
  description = "IAM Role for Lambda"
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
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-${var.stack_name}-lambda-policy"
  description = "IAM Policy for Lambda"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "dynamodb:GetItem"
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
      {
        Action = "dynamodb:PutItem"
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
      {
        Action = "dynamodb:UpdateItem"
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
      {
        Action = "dynamodb:DeleteItem"
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
      {
        Action = "cloudwatch:PutMetricData"
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_role_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.project_name}-${var.stack_name}-amplify-role"
  description = "IAM Role for Amplify"
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
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.project_name}-${var.stack_name}-amplify-policy"
  description = "IAM Policy for Amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "amplify:*"
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_role_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Create API Gateway Deployment
resource "aws_api_gateway_deployment" "api_gateway_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name   = "prod"
}

# Create CloudWatch Logs
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name = "${var.project_name}-${var.stack_name}-api-gateway-log-group"
}

resource "aws_cloudwatch_log_stream" "api_gateway_log_stream" {
  name           = "${var.project_name}-${var.stack_name}-api-gateway-log-stream"
  log_group_name = aws_cloudwatch_log_group.api_gateway_log_group.name
}

# Output Critical Information
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.api_gateway.id}.execute-api.${aws_region}.amazonaws.com/${aws_api_gateway_deployment.api_gateway_deployment.stage_name}"
}

output "lambda_function_name" {
  value = aws_lambda_function.add_item_function.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.amplify_app.id
}

output "amplify_environment_id" {
  value = aws_amplify_environment.amplify_environment.id
}
