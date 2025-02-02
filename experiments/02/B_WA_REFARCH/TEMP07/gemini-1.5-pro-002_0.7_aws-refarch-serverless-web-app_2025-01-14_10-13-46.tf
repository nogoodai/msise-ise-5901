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
  default = "serverless-todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  email_verification_message = "Your verification code is: {####}"
  email_verification_subject = "Verify your email address"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  explicit_auth_flows               = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  generate_secret                   = false
  prevent_user_existence_check_failure = "ENABLED"
  supported_identity_providers      = ["COGNITO"]
  callback_urls                    = ["http://localhost:3000"] # Placeholder
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes              = ["email", "phone", "openid"]
  refresh_token_validity             = 30
}


resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.stack_name}-${random_id.main.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "random_id" "main" {
  byte_length = 8
}

resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
 read_capacity = 5
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

resource "aws_iam_role" "api_gateway_cw_logs" {
  name = "${var.stack_name}-api-gateway-cw-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}


resource "aws_iam_policy" "api_gateway_cw_logs" {
  name        = "${var.stack_name}-api-gateway-cw-logs-policy"
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cw_logs" {
  role       = aws_iam_role.api_gateway_cw_logs.name
  policy_arn = aws_iam_policy.api_gateway_cw_logs.arn
}


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"

}


resource "aws_iam_role" "lambda_dynamodb" {
  name = "${var.stack_name}-lambda-dynamodb-role"
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
  name = "${var.stack_name}-lambda-dynamodb-policy"

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
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:ConditionCheckItem"
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
      },      {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_dynamodb.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}



resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo

  build_spec = {
    platform = "WEB"
  }


}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  name        = var.github_branch
  enable_auto_build = true
}

output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}


output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}
