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

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name                = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id       = aws_cognito_user_pool.main.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls       = ["http://localhost:3000/"] # Placeholder, replace with your actual callback URL
  logout_urls         = ["http://localhost:3000/"] # Placeholder, replace with your actual logout URL
  supported_identity_providers = ["COGNITO"]
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
         "logs:PutLogEvents"
       ],
       Effect   = "Allow",
       Resource = "*"
     }
   ]
 })
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
       Action = [
         "dynamodb:GetItem",
         "dynamodb:PutItem",
         "dynamodb:UpdateItem",
         "dynamodb:DeleteItem",
         "dynamodb:BatchGetItem",
         "dynamodb:BatchWriteItem",
         "dynamodb:Query",
         "dynamodb:Scan"
       ],
       Effect   = "Allow",
       Resource = aws_dynamodb_table.main.arn
     }
   ]
 })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


resource "aws_iam_policy" "lambda_cloudwatch_policy" {
 name = "lambda-cloudwatch-policy-${var.stack_name}"

 policy = jsonencode({
   Version = "2012-10-17",
   Statement = [
     {

       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents",
         "cloudwatch:PutMetricData"
       ],
       Effect   = "Allow",
       Resource = "*"
     }
   ]
 })
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}


# Placeholder for Lambda functions - replace with your actual Lambda function code
resource "aws_lambda_function" "example_lambda" {
  function_name = "example-lambda-${var.stack_name}"
  handler       = "index.handler" # Replace with your handler
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

 # Replace with your actual Lambda function code
  filename      = "lambda_function.zip" # Replace with your zip file
  source_code_hash = filebase64sha256("lambda_function.zip") # Replace with your zip file
}



resource "aws_apigatewayv2_api" "main" {
  name          = "serverless-api-${var.stack_name}"
  protocol_type = "HTTP"
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your Github access token

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
EOF
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
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
