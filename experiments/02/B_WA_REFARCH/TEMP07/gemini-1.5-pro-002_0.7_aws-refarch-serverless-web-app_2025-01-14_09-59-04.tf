terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
 type = string
 default = "todo-app"
}

variable "github_repo_url" {
 type = string
 default = "https://github.com/example/todo-app" # Replace with your GitHub repository URL
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
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id
}



# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"

  user_pool_id = aws_cognito_user_pool.main.id


  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls = ["http://localhost:3000"] # Replace with your callback URL(s)
  logout_urls   = ["http://localhost:3000"] # Replace with your logout URL(s)

  generate_secret = false # Disable client secret

}



# DynamoDB Table
resource "aws_dynamodb_table" "main" {

  name           = "todo-table-${var.stack_name}"


 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5

 attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }

 hash_key  = "cognito-username"
 range_key = "id"


 server_side_encryption {
    enabled = true
 }


}



# IAM Role for API Gateway Logging
resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
  name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
 })
}


# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_dynamodb_role" {
  name = "lambda-dynamodb-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}



resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "lambda-dynamodb-policy-${var.stack_name}"


 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
 "dynamodb:GetItem",
 "dynamodb:PutItem",
 "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
 "dynamodb:Scan",
 "dynamodb:Query",
 "dynamodb:BatchWriteItem",
 "dynamodb:BatchGetItem",
 "dynamodb:DescribeTable"
        ],
        Effect = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },

 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      },

 {
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Effect = "Allow",
 Resource = "*"
 }

    ]
  })


}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_dynamodb_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}




# Placeholder for Lambda functions - replace with your actual Lambda function deployment
resource "aws_lambda_function" "example_lambda" {
  function_name = "example-lambda-${var.stack_name}"
  role          = aws_iam_role.lambda_dynamodb_role.arn
  handler       = "index.handler" # Replace with your Lambda handler
  runtime = "nodejs12.x" # Replace with your desired runtime
 memory_size = 1024
 timeout = 60

 # Replace with your actual Lambda function code
  filename         = "lambda_function.zip" # Example filename
  source_code_hash = filebase64sha256("lambda_function.zip") # Example file

}



# API Gateway Rest API
resource "aws_api_gateway_rest_api" "main" {
 name        = "todo-api-${var.stack_name}"
 description = "API Gateway for Todo App"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

 depends_on = [
    aws_api_gateway_integration.example, # List all your integrations here
 ]
}



# Example API Gateway Integration (replace with your actual integrations)
resource "aws_api_gateway_integration" "example" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.example.id
  http_method            = "ANY"
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"
 integration_uri = aws_lambda_function.example_lambda.invoke_arn

}

# Example API Gateway Resource (replace with your actual resources)
resource "aws_api_gateway_resource" "example" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "{proxy+}"
}

# Example API Gateway Method (replace with your actual methods)
resource "aws_api_gateway_method" "example" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.example.id
  http_method   = "ANY"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito.id

}


# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito_authorizer_${var.stack_name}"
  type          = "COGNITO_USER_POOLS"
  rest_api_id  = aws_api_gateway_rest_api.main.id
 provider_arns = [aws_cognito_user_pool.main.arn]
}



# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
 repository  = var.github_repo_url
 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token
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
  baseDirectory: /
  files:
    - '**/*'
cache:
 paths:
  - node_modules/**/*
EOF
}

# Amplify Branch - master
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true

}



# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
 name = "amplify-role-${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
 Action = "sts:AssumeRole",
 Effect = "Allow",
        Principal = {
 Service = "amplify.amazonaws.com"
 }
      }
    ]
  })
}


# Outputs
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

