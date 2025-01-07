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
  default = "us-west-2"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "environment_name" {
  type    = string
  default = "dev"
}

variable "stack_name" {
  type = string
}


# Cognito
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.environment_name}-user-pool"
  email_verification_message = "Your verification code is {####}"
  verification_message_template {
    default_email_options {
      subject = "Welcome to ${var.application_name}!"
    }
  }

 password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }


  auto_verified_attributes = ["email"]
 tags = {
    Name        = "${var.application_name}-${var.environment_name}-user-pool"
    Environment = var.environment_name
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.environment_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
 allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["phone", "email", "openid"]
  generate_secret                     = false

  callback_urls        = ["http://localhost:3000/"]
  logout_urls          = ["http://localhost:3000/"]
  prevent_user_existence_errors = "ENABLED"
    supported_identity_providers = ["COGNITO"]

 tags = {
    Name        = "${var.application_name}-${var.environment_name}-user-pool-client"
    Environment = var.environment_name
    Project     = var.application_name
  }
}



resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}




# DynamoDB
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
    Environment = var.environment_name
    Project     = var.application_name
  }
}




# IAM
resource "aws_iam_role" "api_gateway_cw_logs" {
  name = "${var.application_name}-${var.environment_name}-api-gateway-cw-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Sid    = "",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_cw_logs" {

  name = "${var.application_name}-${var.environment_name}-api-gateway-cw-logs-policy"
  role = aws_iam_role.api_gateway_cw_logs.id

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


resource "aws_iam_role" "lambda_exec" {

  name = "${var.application_name}-${var.environment_name}-lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

}


resource "aws_iam_policy" "lambda_dynamodb" {
 name = "${var.application_name}-${var.environment_name}-lambda-dynamodb-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
 "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
 "dynamodb:Query",
          "dynamodb:Scan",
 "dynamodb:UpdateItem"
        ],
        Effect   = "Allow",
 Resource = aws_dynamodb_table.main.arn
      }
    ]
  })
}



resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {
 policy_arn = aws_iam_policy.lambda_dynamodb.arn
 role       = aws_iam_role.lambda_exec.name
}




resource "aws_iam_policy" "lambda_cw_metrics" {

 name = "${var.application_name}-${var.environment_name}-lambda-cw-metrics-policy"

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
 Action = [
 "cloudwatch:PutMetricData",
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

resource "aws_iam_role_policy_attachment" "lambda_cw_metrics_attach" {
 policy_arn = aws_iam_policy.lambda_cw_metrics.arn
 role       = aws_iam_role.lambda_exec.name
}





# Lambda Functions

data "archive_file" "lambda_zip" {
 type        = "zip"
  source_dir  = "${path.module}/lambda" # Replace with your Lambda function directory
  output_path = "${path.module}/lambda.zip" # Path for the zip archive
}


resource "aws_lambda_function" "add_item" {
  function_name = "${var.application_name}-${var.environment_name}-add-item"
  filename      = data.archive_file.lambda_zip.output_path
  handler       = "index.handler" # Replace with your Lambda function's handler
  role          = aws_iam_role.lambda_exec.arn
  runtime = "nodejs12.x"

 memory_size = 1024
 timeout = 60
  tracing_config {
    mode = "Active"
  }
}




# API Gateway

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.environment_name}-api"
  description = "API Gateway for ${var.application_name}"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito_authorizer"
  rest_api_id  = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
  type          = "COGNITO_USER_POOLS"
}

# Example resource and method (replace with your actual API resources and methods)
resource "aws_api_gateway_resource" "items" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 parent_id   = aws_api_gateway_rest_api.main.root_resource_id
 path_part   = "items"
}

resource "aws_api_gateway_method" "get_items" {
  rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id   = aws_api_gateway_resource.items.id
  http_method   = "GET"
 authorization = "COGNITO_USER_POOLS" # Or other appropriate authorization type
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}



# Amplify

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


