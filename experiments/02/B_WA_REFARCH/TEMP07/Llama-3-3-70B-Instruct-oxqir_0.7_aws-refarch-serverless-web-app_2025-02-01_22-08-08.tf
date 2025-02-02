# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Configure AWS provider with default region
provider "aws" {
  region = "us-west-2"
}

# Define variables for configuration
variable "stack_name" {
  type        = string
  default     = "serverless-web-app"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/username/repository"
  description = "The GitHub repository URL for the frontend application"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch for the frontend application"
}

# Create Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                     = "${var.stack_name}-user-pool"
  alias_attributes         = ["email"]
  auto_verified_attributes = ["email"]
  email_configuration {
    email_sending_account  = "COGNITO_DEFAULT"
    from_email_address    = "no-reply@example.com"
    reply_to_email_address = "no-reply@example.com"
    source_arn             = aws_iam_role.cognito_email.arn
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                                 = "${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["https://example.com/callback"]
  logout_urls                          = ["https://example.com/logout"]
  supported_identity_providers         = ["COGNITO"]
}

# Create Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain               = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  user_pool_id         = aws_cognito_user_pool.this.id
  certificate_arn      = aws_acm_certificate.this.arn
}

# Create ACM Certificate
resource "aws_acm_certificate" "this" {
  domain_name       = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
  validation_method = "DNS"
}

# Create Route 53 Record
resource "aws_route53_record" "this" {
  name    = "_acme-challenge.${var.stack_name}.auth.us-west-2.amazoncognito.com"
  type    = "CNAME"
  zone_id = aws_route53_zone.this.id
  records = [aws_acm_certificate.this.domain_validation_options[0].resource_record_value]
  ttl     = 300
}

# Create Route 53 Zone
resource "aws_route53_zone" "this" {
  name = "${var.stack_name}.auth.us-west-2.amazoncognito.com"
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
    }
  ]
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Create API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "Serverless Web App API"
}

# Create API Gateway Resource
resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

# Create API Gateway Method
resource "aws_api_gateway_method" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

# Create API Gateway Authorizer
resource "aws_api_gateway_authorizer" "this" {
  name                   = "${var.stack_name}-authorizer"
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.this.arn]
  rest_api_id            = aws_api_gateway_rest_api.this.id
}

# Create API Gateway Integration
resource "aws_api_gateway_integration" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.this.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/${aws_lambda_function.this.arn}/invocations"
}

# Create Lambda Function
resource "aws_lambda_function" "this" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-lambda-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda.arn
  memory_size    = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

# Create IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name        = "${var.stack_name}-lambda-role"
  description = "Execution role for Lambda function"

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

# Create IAM Policy for Lambda
resource "aws_iam_policy" "lambda" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for Lambda function"

  policy = jsonencode({
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

# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# Create IAM Role for API Gateway
resource "aws_iam_role" "api_gateway" {
  name        = "${var.stack_name}-api-gateway-role"
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
      }
    ]
  })
}

# Create IAM Policy for API Gateway
resource "aws_iam_policy" "api_gateway" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "Policy for API Gateway"

  policy = jsonencode({
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

# Attach IAM Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway" {
  role       = aws_iam_role.api_gateway.name
  policy_arn = aws_iam_policy.api_gateway.arn
}

# Create Amplify App
resource "aws_amplify_app" "this" {
  name        = var.stack_name
  description = "Serverless Web App"
}

# Create Amplify Branch
resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

# Create Amplify Environment
resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = aws_amplify_branch.this.branch_name
  environment = "prod"
}

# Create IAM Role for Amplify
resource "aws_iam_role" "amplify" {
  name        = "${var.stack_name}-amplify-role"
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
      }
    ]
  })
}

# Create IAM Policy for Amplify
resource "aws_iam_policy" "amplify" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Policy for Amplify"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateEnvironment",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

# Attach IAM Policy to Amplify Role
resource "aws_iam_role_policy_attachment" "amplify" {
  role       = aws_iam_role.amplify.name
  policy_arn = aws_iam_policy.amplify.arn
}

# Create CloudWatch Log Group
resource "aws_cloudwatch_log_group" "this" {
  name = "${var.stack_name}-log-group"
}

# Create CloudWatch Log Stream
resource "aws_cloudwatch_log_stream" "this" {
  name           = "${var.stack_name}-log-stream"
  log_group_name = aws_cloudwatch_log_group.this.name
}

# Create CloudWatch Metric Alarm
resource "aws_cloudwatch_metric_alarm" "this" {
  alarm_name          = "${var.stack_name}-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 50
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.this.arn]
}

# Create SNS Topic
resource "aws_sns_topic" "this" {
  name = "${var.stack_name}-sns-topic"
}

# Create SNS Subscription
resource "aws_sns_topic_subscription" "this" {
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = "example@example.com"
}

# Output critical information
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "lambda_function_arn" {
  value = aws_lambda_function.this.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.this.branch_name
}
