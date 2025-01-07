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
  default = "us-east-1"
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


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id


  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH"]
  generate_secret     = false
  allowed_oauth_flows_user_pool_client = true

  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_scopes        = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Replace with your callback URL


  prevent_user_existence_errors = "ENABLED"
}




resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
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
    Environment = "production"
    Project     = var.application_name
  }

}


resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

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

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Effect = "Allow",
        Resource = "*"
      },
    ]
  })
}



resource "aws_apigatewayv2_api" "main" {
 name = "serverless-todo-api-${var.stack_name}"
  protocol_type = "HTTP"

}

resource "aws_apigatewayv2_stage" "prod" {
  api_id = aws_apigatewayv2_api.main.id
  name = "prod"
 auto_deploy      = true
}


resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  name             = "cognito-authorizer-${var.stack_name}"
  identity_source = ["$request.header.Authorization"]

 jwt_configuration {
    audience = [aws_cognito_user_pool_client.main.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}


resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"

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
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
 "dynamodb:Scan",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
        ],
        Resource = aws_dynamodb_table.todo_table.arn
      },
 {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ],
 Resource = "*"
      },
      {
        Effect = "Allow",
 Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



resource "aws_lambda_function" "add_item_function" {
  function_name = "add-item-function-${var.stack_name}"
  filename      = "../lambda/add-item/index.zip" # Replace with your Lambda function code path
  handler       = "index.handler" # Replace with your handler function
  runtime       = "nodejs12.x"
 memory_size   = 1024
 timeout       = 60
 role          = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }
}

resource "aws_apigatewayv2_integration" "add_item_integration" {
  api_id             = aws_apigatewayv2_api.main.id
 integration_type   = "aws_proxy"
  integration_method = "POST"
 integration_uri    = aws_lambda_function.add_item_function.invoke_arn
  payload_format_version = "2.0"
}



resource "aws_apigatewayv2_route" "add_item_route" {
 api_id    = aws_apigatewayv2_api.main.id
 route_key = "POST /item"
 target    = "integrations/${aws_apigatewayv2_integration.add_item_integration.id}"
 authorization_type = "JWT"
 authorizer_id = aws_apigatewayv2_authorizer.cognito.id
}



# Create other Lambda functions (get_item, get_all_items, etc.)
# and corresponding API Gateway integrations and routes in a similar fashion.



resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub PAT or use OIDC
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
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOT
}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}



# Add outputs for key resources.
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}


output "api_gateway_url" {
  value = aws_apigatewayv2_api.main.api_endpoint
}


# Add other outputs as needed.

