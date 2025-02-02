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

variable "stack_name" {
  type    = string
  default = "todo-app"
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
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls = ["http://localhost:3000/"] # Placeholder, replace with your actual callback URLs
  logout_urls   = ["http://localhost:3000/"] # Placeholder, replace with your actual logout URLs

  generate_secret = false
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_id.main.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_id" "main" {
 byte_length = 4
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
}



# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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
}

# IAM Policy for DynamoDB access (CRUD)
resource "aws_iam_policy" "dynamodb_crud_policy" {
 name = "${var.stack_name}-dynamodb-crud-policy"
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
 Effect = "Allow",
 Resource = aws_dynamodb_table.main.arn
      },
 ]
 })
}

# Attach DynamoDB CRUD policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_crud_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb_crud_policy.arn
}

# IAM Policy for CloudWatch Logs
resource "aws_iam_policy" "cloudwatch_logs_policy" {
  name = "${var.stack_name}-cloudwatch-logs-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
 Resource = "*"
      },
    ]
 })
}

# Attach CloudWatch Logs policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_logs_attachment" {
 role = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.cloudwatch_logs_policy.arn
}


# Placeholder for Lambda functions - replace with your actual Lambda function code
data "archive_file" "lambda_zip" {
 type = "zip"
 source_dir = "../lambda-functions" # Replace with your Lambda function directory
 output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "lambda_functions" {
 filename         = data.archive_file.lambda_zip.output_path
 function_name = "${var.stack_name}-lambda-function"
 handler = "index.handler" # Replace with your Lambda function handler
 role = aws_iam_role.lambda_role.arn
 runtime = "nodejs12.x" # Replace with your desired runtime
 memory_size = 1024
 timeout = 60
 # Add environment variables, VPC configuration, etc. as needed
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
 description = "API Gateway for ${var.stack_name}"
}


# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

 depends_on = [
 # Add dependencies for API Gateway resources (methods, integrations, etc.)
 ]
}




# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.stack_name}-amplify-app"
  repository = var.github_repo
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your actual GitHub access token

  build_spec = jsonencode({
    version = 0.1,
    settings = {
      buildImage = {
        name = "aws/codebuild/standard:4.0",
        computeType = "BUILD_GENERAL1_SMALL",
      },
    },
 phases = {
      install = {
        "runtime-versions" : {
          "nodejs": 16
        },
 commands = [
 "npm install"
 ]
      },
      preBuild = {
 commands = [
          "npm run build"
 ]
      },
 build = {
 commands = [
          "echo Build started on `date`"
 ]
      },
 postBuild = {
 commands = [
 "echo Build completed on `date`"
 ]
      },
    },
 artifacts = {
      baseDirectory = "/dist",
      files = [
        "*"
      ]
    },
 environment_variables = {
 "ENV" = "testing"
    },
  })
}


# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch

  enable_auto_build = true
}

# IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"
 assume_role_policy = jsonencode({
 Version = "2012-10-17",
 Statement = [
 {
 Action = "sts:AssumeRole",
 Principal = {
 Service = "apigateway.amazonaws.com"
 }
        },
 ]
 })
}

# IAM Policy for API Gateway to write to CloudWatch Logs
resource "aws_iam_policy" "api_gateway_cloudwatch_logs_policy" {

  name = "${var.stack_name}-api-gateway-cw-logs-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
 Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
 ],
 Resource = "*",
 Effect = "Allow"
 }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_logs_policy.arn
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

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

