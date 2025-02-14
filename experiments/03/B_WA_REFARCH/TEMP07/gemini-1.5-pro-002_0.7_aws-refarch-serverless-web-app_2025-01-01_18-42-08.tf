terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

variable "environment" {
  type    = string
  default = "dev"
}

variable "project" {
  type    = string
  default = "todo-app"
}

variable "stack_name" {
  type    = string
  default = "todo-app-stack"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.project}-user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
  }

  tags = {
    Name        = "${var.project}-user-pool"
    Environment = var.environment
    Project     = var.project
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.project}-user-pool-client-${var.stack_name}"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_scopes                      = ["email", "phone", "openid"]


  callback_urls = ["http://localhost:3000/"] # Placeholder, replace with actual callback URL
  logout_urls   = ["http://localhost:3000/"] # Placeholder, replace with actual logout URL


  tags = {
    Name        = "${var.project}-user-pool-client"
    Environment = var.environment
    Project     = var.project
  }
}



# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "cognito-username"
  range_key      = "id"
 attribute_type = ["S"]

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project}-dynamodb-table"
    Environment = var.environment
    Project     = var.project
  }
}




# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-lambda-role-${var.stack_name}"

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
    Name        = "${var.project}-lambda-role"
    Environment = var.environment
    Project     = var.project
  }
}


# IAM Policy for Lambda Functions (DynamoDB Access)
resource "aws_iam_policy" "lambda_dynamodb_policy" {


  name = "${var.project}-lambda-dynamodb-policy-${var.stack_name}"


 policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
 {
        "Sid": "AllowDynamoDBAccess",
        "Effect": "Allow",
        "Action": [
          "dynamodb:BatchGetItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
 "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
 ],
        "Resource": [
 aws_dynamodb_table.main.arn
 ]
      },
      {
        "Effect": "Allow",
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:*:*:*"
      },
 {
        "Effect": "Allow",
        "Action": [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        "Resource": "*"
      }
 ]
  })




  tags = {
    Name        = "${var.project}-lambda-dynamodb-policy"
    Environment = var.environment
    Project     = var.project
  }
}


# Attach DynamoDB Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# Lambda Functions (Example: Add Item) - Create similar resources for other functions
resource "aws_lambda_function" "add_item_function" {
  filename      = "lambda_functions/add_item.zip" # Replace with actual path to zip file
  function_name = "${var.project}-add-item-function-${var.stack_name}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"  # Replace with actual handler name
  runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60
 tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.project}-add-item-function"
    Environment = var.environment
    Project     = var.project
  }
}



# API Gateway - REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project}-api-${var.stack_name}"
  description = "${var.project} API"

  tags = {
    Name        = "${var.project}-api"
    Environment = var.environment
    Project     = var.project
  }
}

# API Gateway - Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
  rest_api_id    = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  provider_arns  = [aws_cognito_user_pool.main.arn]
 authorizer_uri = aws_cognito_user_pool_domain.main.cloudfront_distribution_arn
}

# API Gateway - Resource (Example: /item)
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

# API Gateway - Method (Example: POST /item)
resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
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
  integration_method = "POST"
  request_templates = {
    "application/json" = jsonencode({
      statusCode: 200
    })
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

  depends_on = [
    aws_api_gateway_integration.post_item_integration,

  ]
}



# API Gateway - Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"


  tags = {
    Name        = "${var.project}-api-stage"
    Environment = var.environment
    Project     = var.project
  }

}

# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.project}-amplify-app-${var.stack_name}"
  repository = var.github_repo
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with actual token
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
    Name        = "${var.project}-amplify-app"
    Environment = var.environment
    Project     = var.project
  }
}



# Amplify Branch (Master Branch)
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

 tags = {
    Name        = "${var.project}-amplify-branch"
    Environment = var.environment
    Project     = var.project
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
