provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "serverless-web-app"
}

variable "application_name" {
  type        = string
  default     = "todo-list"
}

variable "github_repository" {
  type        = string
  default     = "https://github.com/user/todo-list-frontend"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

# Create Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                            = "${var.stack_name}-user-pool"
  emailVerificationMessage       = "Your verification code is {####}."
  emailVerificationSubject        = "Your verification code"
  auto_verified_attributes       = ["email"]
  alias_attributes               = ["email"]
  password_policy {
    minimum_length                = 6
    require_uppercase             = true
    require_lowercase             = true
    require_symbols               = false
    require_numbers               = false
  }
  tags = {
    Name                            = "${var.stack_name}-user-pool"
    Environment                     = "prod"
    Project                         = var.application_name
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                            = "${var.stack_name}-user-pool-client"
  user_pool_id                    = aws_cognito_user_pool.this.id
  generate_secret                = false
  allowed_oauth_flows            = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool  = true
  allowed_oauth_scopes           = ["email", "phone", "openid"]
}

# Create Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "this" {
  domain                      = "${var.application_name}-${var.stack_name}"
  user_pool_id                = aws_cognito_user_pool.this.id
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name                            = "todo-table-${var.stack_name}"
  billing_mode                    = "PROVISIONED"
  read_capacity_units            = 5
  write_capacity_units           = 5
  hash_key                       = "cognito-username"
  range_key                      = "id"
  attribute {
    name                          = "cognito-username"
    type                          = "S"
  }
  attribute {
    name                          = "id"
    type                          = "S"
  }
  server_side_encryption {
    enabled                       = true
  }
  tags = {
    Name                            = "todo-table-${var.stack_name}"
    Environment                     = "prod"
    Project                         = var.application_name
  }
}

# Create API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name                            = "${var.stack_name}-api-gateway"
  description                    = "API Gateway for ${var.stack_name}"
  tags = {
    Name                            = "${var.stack_name}-api-gateway"
    Environment                     = "prod"
    Project                         = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "this" {
  name                            = "${var.stack_name}-authorizer"
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  type                            = "COGNITO_USER_POOLS"
  provider_arns                  = [aws_cognito_user_pool.this.arn]
}

# Create API Gateway Stage
resource "aws_api_gateway_stage" "this" {
  stage_name                     = "prod"
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  deployment_id                  = aws_api_gateway_deployment.this.id
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  stage_name                     = "prod"
}

# Create API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "this" {
  name                            = "${var.stack_name}-usage-plan"
  description                    = "Usage plan for ${var.stack_name}"
  api_stages {
    api_id                        = aws_api_gateway_rest_api.this.id
    stage_name                    = aws_api_gateway_stage.this.stage_name
  }
  quota {
    limit                          = 5000
    period                        = "DAY"
  }
  throttle {
    burst_limit                   = 100
    rate_limit                    = 50
  }
}

# Create Lambda Function
resource "aws_lambda_function" "add_item" {
  filename                        = "${path.module}/lambda_function_payload.zip"
  function_name                  = "${var.stack_name}-add-item"
  handler                        = "index.handler"
  runtime                        = "nodejs12.x"
  role                           = aws_iam_role.lambda_exec.arn
  memory_size                    = 1024
  timeout                        = 60
  tracing_config {
    mode                          = "Active"
  }
}

resource "aws_lambda_function" "get_item" {
  filename                        = "${path.module}/lambda_function_payload.zip"
  function_name                  = "${var.stack_name}-get-item"
  handler                        = "index.handler"
  runtime                        = "nodejs12.x"
  role                           = aws_iam_role.lambda_exec.arn
  memory_size                    = 1024
  timeout                        = 60
  tracing_config {
    mode                          = "Active"
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename                        = "${path.module}/lambda_function_payload.zip"
  function_name                  = "${var.stack_name}-get-all-items"
  handler                        = "index.handler"
  runtime                        = "nodejs12.x"
  role                           = aws_iam_role.lambda_exec.arn
  memory_size                    = 1024
  timeout                        = 60
  tracing_config {
    mode                          = "Active"
  }
}

resource "aws_lambda_function" "update_item" {
  filename                        = "${path.module}/lambda_function_payload.zip"
  function_name                  = "${var.stack_name}-update-item"
  handler                        = "index.handler"
  runtime                        = "nodejs12.x"
  role                           = aws_iam_role.lambda_exec.arn
  memory_size                    = 1024
  timeout                        = 60
  tracing_config {
    mode                          = "Active"
  }
}

resource "aws_lambda_function" "complete_item" {
  filename                        = "${path.module}/lambda_function_payload.zip"
  function_name                  = "${var.stack_name}-complete-item"
  handler                        = "index.handler"
  runtime                        = "nodejs12.x"
  role                           = aws_iam_role.lambda_exec.arn
  memory_size                    = 1024
  timeout                        = 60
  tracing_config {
    mode                          = "Active"
  }
}

resource "aws_lambda_function" "delete_item" {
  filename                        = "${path.module}/lambda_function_payload.zip"
  function_name                  = "${var.stack_name}-delete-item"
  handler                        = "index.handler"
  runtime                        = "nodejs12.x"
  role                           = aws_iam_role.lambda_exec.arn
  memory_size                    = 1024
  timeout                        = 60
  tracing_config {
    mode                          = "Active"
  }
}

# Create IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name                            = "${var.stack_name}-api-gateway-exec"
  assume_role_policy              = jsonencode({
    Version                       = "2012-10-17"
    Statement                    = [
      {
        Action                    = "sts:AssumeRole"
        Effect                     = "Allow"
        Principal                 = {
          Service                  = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "api_gateway_exec" {
  name                            = "${var.stack_name}-api-gateway-exec"
  policy                         = jsonencode({
    Version                       = "2012-10-17"
    Statement                    = [
      {
        Action                    = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect                     = "Allow"
        Resource                  = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role                            = aws_iam_role.api_gateway_exec.name
  policy_arn                     = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name                            = "${var.stack_name}-lambda-exec"
  assume_role_policy              = jsonencode({
    Version                       = "2012-10-17"
    Statement                    = [
      {
        Action                    = "sts:AssumeRole"
        Effect                     = "Allow"
        Principal                 = {
          Service                  = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_exec" {
  name                            = "${var.stack_name}-lambda-exec"
  policy                         = jsonencode({
    Version                       = "2012-10-17"
    Statement                    = [
      {
        Action                    = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect                     = "Allow"
        Resource                  = "*"
      },
      {
        Action                    = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect                     = "Allow"
        Resource                  = aws_dynamodb_table.this.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role                            = aws_iam_role.lambda_exec.name
  policy_arn                     = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name                            = "${var.stack_name}-amplify-exec"
  assume_role_policy              = jsonencode({
    Version                       = "2012-10-17"
    Statement                    = [
      {
        Action                    = "sts:AssumeRole"
        Effect                     = "Allow"
        Principal                 = {
          Service                  = "amplify.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "amplify_exec" {
  name                            = "${var.stack_name}-amplify-exec"
  policy                         = jsonencode({
    Version                       = "2012-10-17"
    Statement                    = [
      {
        Action                    = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
        ]
        Effect                     = "Allow"
        Resource                  = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role                            = aws_iam_role.amplify_exec.name
  policy_arn                     = aws_iam_policy.amplify_exec.arn
}

# Create Amplify App
resource "aws_amplify_app" "this" {
  name                            = var.application_name
  description                    = "Amplify app for ${var.application_name}"
  platform                       = "WEB"
  build_spec                     = "{\"version\":\"0.1.0\",\"frontend\":\"frontend\",\"backend\":{\" phases\":{\"build\":[\"npm install\",\"npm run build\"]},\"artifacts\":{\"baseDirectory\":\"build\",\"files\":[\"**/*\"]},\"cache\":{\"paths\":[\"node_modules/**/*\"]}}}"
  tags                            = {
    Name                            = var.application_name
    Environment                     = "prod"
    Project                         = var.application_name
  }
}

# Create Amplify Branch
resource "aws_amplify_branch" "this" {
  app_id                          = aws_amplify_app.this.id
  branch_name                    = var.github_branch
}

# Create API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "add_item" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  resource_id                    = aws_api_gateway_resource.this.id
  http_method                    = "POST"
  integration_http_method        = "POST"
  type                            = "LAMBDA"
  uri                             = "arn:aws:apigateway:${aws_region}.lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  resource_id                    = aws_api_gateway_resource.get_item.id
  http_method                    = "GET"
  integration_http_method        = "GET"
  type                            = "LAMBDA"
  uri                             = "arn:aws:apigateway:${aws_region}.lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_all_items" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  resource_id                    = aws_api_gateway_resource.get_all_items.id
  http_method                    = "GET"
  integration_http_method        = "GET"
  type                            = "LAMBDA"
  uri                             = "arn:aws:apigateway:${aws_region}.lambda:path/2015-03-31/functions/${aws_lambda_function.get_all_items.arn}/invocations"
}

resource "aws_api_gateway_integration" "update_item" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  resource_id                    = aws_api_gateway_resource.update_item.id
  http_method                    = "PUT"
  integration_http_method        = "PUT"
  type                            = "LAMBDA"
  uri                             = "arn:aws:apigateway:${aws_region}.lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "complete_item" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  resource_id                    = aws_api_gateway_resource.complete_item.id
  http_method                    = "POST"
  integration_http_method        = "POST"
  type                            = "LAMBDA"
  uri                             = "arn:aws:apigateway:${aws_region}.lambda:path/2015-03-31/functions/${aws_lambda_function.complete_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  resource_id                    = aws_api_gateway_resource.delete_item.id
  http_method                    = "DELETE"
  integration_http_method        = "DELETE"
  type                            = "LAMBDA"
  uri                             = "arn:aws:apigateway:${aws_region}.lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  parent_id                      = aws_api_gateway_rest_api.this.root_resource_id
  path_part                      = "item"
}

resource "aws_api_gateway_resource" "get_item" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  parent_id                      = aws_api_gateway_resource.this.id
  path_part                      = "{id}"
}

resource "aws_api_gateway_resource" "get_all_items" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  parent_id                      = aws_api_gateway_rest_api.this.root_resource_id
  path_part                      = "items"
}

resource "aws_api_gateway_resource" "update_item" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  parent_id                      = aws_api_gateway_resource.this.id
  path_part                      = "{id}"
}

resource "aws_api_gateway_resource" "complete_item" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  parent_id                      = aws_api_gateway_resource.this.id
  path_part                      = "{id}/done"
}

resource "aws_api_gateway_resource" "delete_item" {
  rest_api_id                    = aws_api_gateway_rest_api.this.id
  parent_id                      = aws_api_gateway_resource.this.id
  path_part                      = "{id}"
}

# Create Outputs
output "cognito_user_pool_id" {
  value                           = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value                           = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_arn" {
  value                           = aws_dynamodb_table.this.arn
}

output "api_gateway_id" {
  value                           = aws_api_gateway_rest_api.this.id
}

output "api_gateway_stage_name" {
  value                           = aws_api_gateway_stage.this.stage_name
}

output "lambda_function_arns" {
  value                           = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn,
  ]
}

output "amplify_app_id" {
  value                           = aws_amplify_app.this.id
}

output "amplify_branch_name" {
  value                           = aws_amplify_branch.this.branch_name
}
