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

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
 type = string
 default = "main"
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain      = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                = aws_cognito_user_pool.main.id
  generate_secret              = false
 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows          = ["code", "implicit"]
  allowed_oauth_scopes         = ["email", "phone", "openid"]
  callback_urls                = ["http://localhost:3000/"] # Placeholder - update with actual frontend URL
  refresh_token_validity = 30 # days
  prevent_user_existence_errors = "enabled"
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  hash_key = "cognito-username"
  range_key = "id"

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
    Environment = "prod"
    Project     = var.application_name
  }
}

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-lambda-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
 Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
 Sid    = ""
      },
    ]
  })

  tags = {
    Name = "${var.application_name}-lambda-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# IAM Policy for Lambda function (DynamoDB access and CloudWatch Logs)
resource "aws_iam_policy" "lambda_policy" {
  name = "${var.application_name}-lambda-policy-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
 Action = [
 "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
 "dynamodb:Scan",
 "dynamodb:Query",
          "dynamodb:BatchWriteItem",
 "dynamodb:BatchGetItem"
        ],
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
 ],
 Resource = "arn:aws:logs:*:*:*"
      },
 {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
 ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
 "cloudwatch:PutMetricData"
 ],
 Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# Placeholder for Lambda functions - replace with your actual function code
resource "aws_lambda_function" "add_item" {
  function_name = "${var.application_name}-add-item-${var.stack_name}"
  handler = "index.handler" # Replace with your handler
  role    = aws_iam_role.lambda_role.arn
  runtime = "nodejs12.x"
 memory_size = 1024
  timeout      = 60
  tracing_config {
 mode = "Active"
  }

 # Replace with your actual function code
  filename         = "dummy_lambda.zip"
 source_code_hash = filebase64sha256("dummy_lambda.zip")
}



# IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-api-gateway-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
 Action = "sts:AssumeRole",
        Principal = {
 Service = "apigateway.amazonaws.com"
        },
        Effect = "Allow",
 Sid    = ""
      },
    ]
  })
  tags = {
    Name = "${var.application_name}-api-gateway-role-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }

}


# IAM Policy for API Gateway (CloudWatch Logs)

resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {


  name = "${var.application_name}-api-gateway-cw-policy-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17",
 Statement = [
 {
 Effect = "Allow",
 Action = [
 "logs:CreateLogGroup",
            "logs:CreateLogStream",
 "logs:PutLogEvents"
 ],
 Resource = "*"
 }
    ]

  })
}



resource "aws_iam_role_policy_attachment" "api_gateway_cw_policy_attachment" {
  role = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}


# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {

  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
}




# API Gateway Method - Add Item
resource "aws_api_gateway_method" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = "POST"
 authorization_type = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito.id
}

# API Gateway Integration - Add Item
resource "aws_api_gateway_integration" "add_item" {

  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.add_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"

  credentials = aws_iam_role.api_gateway_role.arn
  request_templates = {
    "application/json" = jsonencode( {
      statusCode = 200
    })
  }

 integration_uri = aws_lambda_function.add_item.invoke_arn
}


# API Gateway Resource for all paths
resource "aws_api_gateway_resource" "proxy" {

  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "{proxy+}"
}



# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {

  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body))
  }

 lifecycle {
 create_before_destroy = true
  }
}


# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {


  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

}


resource "aws_api_gateway_usage_plan" "myusageplan" {
 name         = "${var.application_name}-usage-plan-${var.stack_name}"
 description  = "Usage plan for ${var.application_name}"
 product_code = "MYCODE"


 throttle_settings {
    burst_limit = 100
 rate_limit = 50
  }

  quota_settings {

    limit  = 5000
    offset = 0
 period = "DAY"
  }

}



# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito" {


  name            = "${var.application_name}-cognito-authorizer-${var.stack_name}"
  rest_api_id    = aws_api_gateway_rest_api.main.id
  provider_arns  = [aws_cognito_user_pool.main.arn]
  type           = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"
}

# Amplify App
resource "aws_amplify_app" "main" {

  name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace or use environment variable
 build_spec = <<-EOT
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
    baseDirectory: /
    files:
      - '**/*'
  cache:
 paths:
      - node_modules/**/*

EOT

  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "prod"
 Project = var.application_name
  }

}



# Amplify Branch - master
resource "aws_amplify_branch" "master" {

  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true

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

