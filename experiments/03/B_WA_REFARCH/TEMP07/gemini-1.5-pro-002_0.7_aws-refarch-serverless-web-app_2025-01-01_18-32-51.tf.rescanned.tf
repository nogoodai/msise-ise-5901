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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
 description = "The application's name, used for naming resources."
  default     = "todo-app"
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  description = "The branch of the GitHub repository to use."
  default     = "master"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  auto_verified_attributes = ["email"]
  mfa_configuration = "OFF" # Explicitly set MFA to OFF
  password_policy {
    minimum_length = 12 # Increased minimum length
 require_lowercase = true
    require_numbers   = true # Require numbers in password
 require_symbols    = true # Require symbols
 require_uppercase = true
  }

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "production" # Example environment tag
    Project     = "todo-app" # Example project tag
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

  prevent_user_existence_errors = "ENABLED"

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id


  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = "production"
 Project     = "todo-app"
  }
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  hash_key       = "cognito-username"
 range_key      = "id"
  billing_mode   = "PAY_PER_REQUEST"
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

 point_in_time_recovery {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
 minimum_compression_size = 0
 tags = {
    Name = "${var.application_name}-api-${var.stack_name}"
 Environment = "production"
 Project = "todo-app"
  }
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

  tags = {
 Name = "api-gateway-cloudwatch-logs-${var.stack_name}"
    Environment = "production"
    Project = "todo-app"
  }
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
 Resource = aws_cloudwatch_log_group.main.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "main" {
 name              = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
  retention_in_days = 30 # Adjust retention as needed
}


resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_logs_role.arn
}



# Placeholder Lambda functions - replace with actual Lambda function code
resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  handler       = "index.handler"
 runtime = "nodejs16.x" # Updated runtime
 timeout = 30 # Reduced timeout
 memory = 128 # Reduced memory
 role = aws_iam_role.lambda_exec_role.arn

  # Replace with actual code
 filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name = "add-item-${var.stack_name}"
 Environment = "production"
 Project = "todo-app"
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
 tags = {
    Name = "lambda_exec_role_${var.stack_name}"
    Environment = "production"
    Project = "todo-app"
 }
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
 "dynamodb:DeleteItem"
 ],
 Resource = aws_dynamodb_table.main.arn
 },
    ]
  })

  tags = {
    Name = "lambda_dynamodb_policy_${var.stack_name}"
 Environment = "production"
 Project = "todo-app"
  }
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
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
 "logs:CreateLogStream",
          "logs:PutLogEvents"

        ],
        Resource = "*"
      },
    ]
  })
 tags = {
    Name = "lambda_cloudwatch_policy_${var.stack_name}"
    Environment = "production"
    Project = "todo-app"
  }
}


resource "aws_iam_policy_attachment" "lambda_cloudwatch_policy_attachment" {
 name       = "lambda_cloudwatch_policy_attachment_${var.stack_name}"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo_url
  tags = {
 Name = "${var.application_name}-amplify-${var.stack_name}"
 Environment = "production"
 Project = "todo-app"
  }
}


resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
  branch_name         = var.github_repo_branch
  enable_auto_build = true
}


output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
 description = "The ID of the Cognito User Pool Client."
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
  description = "The ID of the API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
 description = "The ID of the Amplify app."
}

