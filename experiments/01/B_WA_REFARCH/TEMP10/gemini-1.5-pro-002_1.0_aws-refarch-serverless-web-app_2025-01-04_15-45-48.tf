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

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]


}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
}


resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "main" {
  name = "todo-table-${var.stack_name}"

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
  name = "api-gateway-cw-logs-${var.stack_name}"

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


resource "aws_iam_role_policy" "api_gateway_cw_logs" {
  name = "api-gateway-cw-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_logs.id

 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_api_gateway_rest_api" "main" {
  name = "${var.application_name}-${var.stack_name}-api"
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
  rest_api_id   = aws_api_gateway_rest_api.main.id
}


resource "aws_iam_role" "lambda_dynamodb" {

  name = "lambda-dynamodb-${var.stack_name}"
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


resource "aws_iam_policy" "lambda_dynamodb" {

  name = "lambda-dynamodb-policy-${var.stack_name}"

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
 "dynamodb:Scan",
 "dynamodb:Query"
        ],
        Resource = aws_dynamodb_table.main.arn
      },
            {
        Effect = "Allow",
        Action = [
 "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attach" {

  role       = aws_iam_role.lambda_dynamodb.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url

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
  baseDirectory: build
  files:
  - '**/*'
EOF

}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
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


