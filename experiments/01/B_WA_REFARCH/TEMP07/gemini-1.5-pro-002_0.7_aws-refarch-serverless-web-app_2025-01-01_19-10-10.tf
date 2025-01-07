terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

 verification_message_template {
    default_email_options {
      sms_verification_message = "Your verification code is {####}"
    }
  }


 auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}



# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Update with your callback URL
  logout_urls          = ["http://localhost:3000/"] # Update with your logout URL
  supported_identity_providers = ["COGNITO"]
  prevent_user_existence_errors = "ENABLED"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
 read_capacity = 5
 write_capacity = 5
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
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-role"

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

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Policy for Lambda function (DynamoDB access)

resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "${var.application_name}-${var.stack_name}-lambda-dynamodb-policy"


  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowDynamoDBAccess",
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem"
        ],
        "Resource" : aws_dynamodb_table.main.arn
      }
    ]
  })


}



resource "aws_iam_policy_attachment" "lambda_dynamodb_attachment" {
  name       = "${var.application_name}-${var.stack_name}-lambda-dynamodb-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


# IAM Policy for Lambda function (CloudWatch Logs access)
resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name = "${var.application_name}-${var.stack_name}-lambda-cloudwatch-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*",
        "Effect" : "Allow"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_cloudwatch_attachment" {
  name       = "${var.application_name}-${var.stack_name}-lambda-cloudwatch-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}


# Lambda Function (Example: Add Item) - Replace with your Lambda function code
resource "aws_lambda_function" "add_item_function" {
  function_name = "${var.application_name}-${var.stack_name}-add-item-function"
  handler = "index.handler" # Replace with your handler
  runtime = "nodejs12.x"
 memory_size = 1024
  timeout = 60

  role    = aws_iam_role.lambda_role.arn

# Replace with your actual Lambda function code
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
  tracing_config {
    mode = "Active"
  }
 tags = {
    Name        = "${var.application_name}-${var.stack_name}-add-item-function"
    Environment = var.stack_name
    Project     = var.application_name
  }

}



# API Gateway - REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway - Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}


# API Gateway - Resource (Example: /item)
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

# API Gateway - Method (Example: POST /item)
resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.item_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

# API Gateway - Integration (Example: POST /item)
resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.post_item_method.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"
  credentials = aws_iam_role.lambda_role.arn

  integration_method = "POST"
  request_templates = {
    "application/json" = <<EOF
{
  "statusCode" : 200
}
EOF
  }
  request_parameters = {
    "integration.request.path.id" = "method.request.path.id"
  }
}


# API Gateway - Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway - Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-stage-prod"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo
  access_token = "your_github_access_token" # Replace with your GitHub Personal Access Token
 build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify Branch - Master
resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true


  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-branch-master"
    Environment = var.stack_name
    Project     = var.application_name
  }
}



output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.main.invoke_url
}


output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}
