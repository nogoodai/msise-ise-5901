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
  type = string
}

variable "application_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls                         = ["http://localhost:3000/"] # Placeholder, update as needed
  supported_identity_providers        = ["COGNITO"]
}


resource "aws_dynamodb_table" "main" {
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
   Environment = var.stack_name
   Project     = var.application_name
 }
}

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}


resource "aws_apigatewayv2_api" "main" {
 name     = "${var.application_name}-${var.stack_name}-api"
 protocol_type = "HTTP"

 cors_configuration {
   allow_headers = ["*"]
   allow_methods = ["*"]
   allow_origins = ["*"]
 }
}

resource "aws_apigatewayv2_stage" "prod" {
 api_id      = aws_apigatewayv2_api.main.id
 name        = "prod"
 auto_deploy = true

 access_log_settings {
   destination_arn = aws_cloudwatch_log_group.api_gateway.arn
   format = jsonencode({
     requestId = "$context.requestId",
     ip        = "$context.identity.sourceIp",
     requestTime = "$context.requestTime",
     httpMethod = "$context.httpMethod",
     routeKey = "$context.routeKey",
     status = "$context.status",
     protocol = "$context.protocol",
     responseLength = "$context.responseLength"
   })
 }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "/aws/apigateway/${aws_apigatewayv2_api.main.name}"
  retention_in_days = 30
}


# Placeholder for Lambda functions and integrations - replace with actual Lambda code and integrations
# Example Lambda function resource (replace with your actual Lambda functions)

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


resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
 name = "lambda-dynamodb-policy-${var.stack_name}"
 role = aws_iam_role.lambda_role.id

 policy = jsonencode({
   Version = "2012-10-17",
   Statement = [
     {
       Action = [
         "dynamodb:GetItem",
         "dynamodb:PutItem",
         "dynamodb:UpdateItem",
         "dynamodb:DeleteItem",
         "dynamodb:BatchGetItem",
         "dynamodb:BatchWriteItem",
         "dynamodb:Query",
         "dynamodb:Scan",
       ],
       Effect   = "Allow",
       Resource = aws_dynamodb_table.main.arn
     },
     {
       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents"
       ],
       Effect = "Allow",
       Resource = "arn:aws:logs:*:*:*"
     },
     {
       Action = [
         "xray:PutTraceSegments",
         "xray:PutTelemetryRecords"
       ],
       Effect = "Allow",
       Resource = "*"
     }
   ]
 })
}

resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token or use a secrets management solution
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
     postBuild:
       commands:
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF
 custom_rules = [
 {
   source = "/<*>"
   target = "/index.html"
   status = 200
 }
 ]

}


resource "aws_s3_bucket" "main" {
 bucket = "${var.application_name}-${var.stack_name}-amplify-bucket"
 acl    = "private"
}

resource "aws_amplify_branch" "main" {
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
 value = aws_apigatewayv2_api.main.api_endpoint
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}
