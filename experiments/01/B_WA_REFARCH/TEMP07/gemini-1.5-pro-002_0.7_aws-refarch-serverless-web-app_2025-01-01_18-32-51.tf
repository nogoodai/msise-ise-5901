terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
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

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name               = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id      = aws_cognito_user_pool.main.id
  generate_secret   = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Placeholder, replace with actual callback URL
  logout_urls    = ["http://localhost:3000/"] # Placeholder, replace with actual logout URL
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  hash_key       = "cognito-username"
  range_key      = "id"
 billing_mode = "PROVISIONED"
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

 server_side_encryption {
    enabled = true
  }

}

resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name                   = "cognito_authorizer"
  rest_api_id            = aws_api_gateway_rest_api.main.id
  provider_arns          = [aws_cognito_user_pool.main.arn]
  type                   = "COGNITO"
  identity_source        = "method.request.header.Authorization"
}


resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

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
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
 name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ],
        Resource = "*"
      },
    ]
  })
}

resource "aws_api_gateway_account" "main" {
 cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_logs_role.arn
}



# Placeholder Lambda functions - replace with actual Lambda function code
resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler"
  runtime = "nodejs12.x" # Replace with desired runtime
 memory = 1024
 timeout = 60
  role          = aws_iam_role.lambda_exec_role.arn

  # Replace with actual code
  filename      = data.archive_file.lambda_zip.output_path
 source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tracing_config {
    mode = "Active"
  }
}

data "archive_file" "lambda_zip" {
 type        = "zip"
 output_path = "${path.module}/lambda.zip"
 source_dir  = "${path.module}/lambda_function_code/" # Replace with the directory containing your Lambda function code
}


resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role_${var.stack_name}"

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


resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda_dynamodb_policy_${var.stack_name}"
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
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
 "dynamodb:DescribeTable"
        ],
        Resource = aws_dynamodb_table.main.arn
      },
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_dynamodb_policy_attachment" {
 name       = "lambda_dynamodb_policy_attachment_${var.stack_name}"
 roles      = [aws_iam_role.lambda_exec_role.name]
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
 name = "lambda_cloudwatch_policy_${var.stack_name}"
 policy = jsonencode({

    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
 "cloudwatch:PutMetricData"
 ],
        Resource = "*"
      },
    ]
  })
}


resource "aws_iam_policy_attachment" "lambda_cloudwatch_policy_attachment" {
  name       = "lambda_cloudwatch_policy_attachment_${var.stack_name}"
 roles      = [aws_iam_role.lambda_exec_role.name]
 policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}

resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo_url
}


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

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}


output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


