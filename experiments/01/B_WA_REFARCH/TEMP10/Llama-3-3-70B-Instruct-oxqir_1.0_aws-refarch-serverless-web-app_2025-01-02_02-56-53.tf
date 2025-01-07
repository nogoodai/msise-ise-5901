# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "= 2.2.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# Variables
variable "stack_name" {
  default = "serverless-web-app"
}
variable "github_token" {
  default = ""
}
variable "github_repo" {
  default = ""
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.stack_name}-user-pool"
  email_configuration = {
    email_sending_account = "DEVELOPER"
    from_email_address    = "noreply@${var.stack_name}.example.com"
    reply_to_email_address = "noreply@${var.stack_name}.example.com"
  }
  alias_attributes  = ["email"]
  password_policy = {
    minimum_length      = 6
    require_uppercase   = true
    require_lowercase   = true
    require_numbers     = false
    require_symbols     = false
  }
  username_attributes = ["email"]
  username_configuration = {
    case_sensitivity = "None"
  }
  schema = [
    {
      name                     = "email"
      attribute_data_type      = "String"
      developer_only_attribute = false
      mutable                  = false
      required                 = true
    }
  ]
  verification_message_template = {
    default_email_option = "CONFIRM_WITH_LINK"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.this.id

  supported_identity_providers = ["COGNITO"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  allowed_oauth_flows_client_credentials = false
  generate_secret                      = false
}

# Custom Domain for Cognito User Pool
resource "aws_route53_record" "this" {
  zone_id = aws_route53_zone.this.id
  name    = "${var.stack_name}.example.com"
  type    = "A"

  alias {
    name = aws_cognito_user_pool_domain.this.cloudfront_distribution_arn
    zone_id = aws_cognito_user_pool_domain.this.cloudfront_distribution_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}.example.com"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_route53_zone" "this" {
  name = "example.com"
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
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

  point_in_time_recovery {
    enabled = false
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = false
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name = "${var.stack_name}-rest-api"
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_integration" "post" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "put" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_integration.post,
    aws_api_gateway_integration.get,
    aws_api_gateway_integration.put,
    aws_api_gateway_integration.delete
  ]

  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_functions/add_item.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_functions/get_item.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_functions/get_all_items.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_functions/update_item.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_functions/complete_item.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_functions/delete_item.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = var.stack_name
  description = "${var.stack_name} Amplify App"

  tags = {
    Environment = "prod"
  }
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"

  stage = "PRODUCTION"
}

# IAM Roles and Policies
resource "aws_iam_role" "lambda" {
  name        = "${var.stack_name}-lambda-role"
  description = "Execution role for Lambda functions"

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

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "dynamodb-crud" {
  name        = "${var.stack_name}-dynamodb-crud-policy"
  description = "DynamoDB CRUD policy for Lambda functions"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:us-west-2:*:table/todo-table-${var.stack_name}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dynamodb-crud" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.dynamodb-crud.arn
}

resource "aws_iam_policy" "cloudwatch-metrics" {
  name        = "${var.stack_name}-cloudwatch-metrics-policy"
  description = "CloudWatch metrics policy for Lambda functions"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch-metrics" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.cloudwatch-metrics.arn
}

resource "aws_iam_role" "api-gateway" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "Execution role for API Gateway"

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

resource "aws_iam_role_policy_attachment" "api-gateway" {
  role       = aws_iam_role.api-gateway.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify" {
  name        = "${var.stack_name}-amplify-role"
  description = "Execution role for Amplify"

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

resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonAmplifyServiceRolePolicy"
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

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "api_gateway_deployment_id" {
  value = aws_api_gateway_deployment.this.id
}

output "lambda_functions" {
  value = [
    aws_lambda_function.add_item.arn,
    aws_lambda_function.get_item.arn,
    aws_lambda_function.get_all_items.arn,
    aws_lambda_function.update_item.arn,
    aws_lambda_function.complete_item.arn,
    aws_lambda_function.delete_item.arn
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}
