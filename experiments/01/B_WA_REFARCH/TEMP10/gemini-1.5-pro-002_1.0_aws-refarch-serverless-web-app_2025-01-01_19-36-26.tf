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
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
 minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_domain" "main" {
 domain      = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false


  callback_urls        = ["http://localhost:3000/"] # Update with your callback URLs
  logout_urls          = ["http://localhost:3000/"] # Update with your logout URLs
  allowed_provider_identifiers = ["cognito-idp.us-east-1.amazonaws.com/${aws_cognito_user_pool.main.id}"] # Update with Cognito Pool

}


# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
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
}




# IAM Roles and Policies

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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
  name = "${var.stack_name}-api-gateway-cw-logs-policy"
  role = aws_iam_role.api_gateway_role.id

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
      },
    ]
  })
}


resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.stack_name}-lambda-execution-role"


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



resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}



resource "aws_iam_policy" "lambda_dynamodb_policy" {

 name = "${var.stack_name}-lambda-dynamodb-policy"



  policy = jsonencode({

    Version = "2012-10-17",
    Statement = [
      {
        Action = [
 "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
 "dynamodb:Scan", # Add scan permission
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.todo_table.arn
      },
    ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
 role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


# API Gateway
resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.stack_name}-api"
 description = "API Gateway for ${var.stack_name}"
}


resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
  rest_api_id    = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  provider_arns  = [aws_cognito_user_pool.main.arn]
}



# Lambda Functions (Example: Add Item)
resource "aws_lambda_function" "add_item_function" {
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler" # Replace with your handler
  runtime = "nodejs12.x"
  memory_size = 1024
  timeout = 60
  role = aws_iam_role.lambda_execution_role.arn

# Replace with your function's code
 source_code_hash = filebase64sha256("lambda_function_zip.zip") # Example
  filename         = "lambda_function_zip.zip" # Example

  tracing_config {
    mode = "Active"
  }
}

# Example API Gateway integration for Add Item function
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}



resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_resource.id
 http_method             = aws_api_gateway_method.post_item_method.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"

 integration_uri = aws_lambda_function.add_item_function.invoke_arn
}





# (Add other Lambda functions and API Gateway resources similarly)


# Amplify App
resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo_url
  access_token = var.github_access_token  # Please ensure you added this as an environment variable. You should avoid including sensitive information directly in the code.

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

resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.main.id
  branch_name   = var.github_repo_branch
  enable_auto_build = true
}



output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

# ... other outputs as needed
