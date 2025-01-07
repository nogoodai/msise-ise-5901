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
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}

variable "application_name" {
  type    = string
  default = "todo-app"
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
  name         = "${var.application_name}-${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_dynamodb_table" "main" {
 name         = "todo-table-${var.stack_name}"
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

resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"

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

resource "aws_iam_role_policy" "api_gateway_cw_policy" {
  name = "api-gateway-cw-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_role.id

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
      },
    ]
  })
}

resource "aws_apigatewayv2_api" "main" {
 name = "serverless-todo-api-${var.stack_name}"
 protocol_type = "HTTP"
}


resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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
         "dynamodb:BatchWriteItem",
         "dynamodb:Query",
         "dynamodb:Scan"
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
     },
     {
       Effect = "Allow",
       Action = [
         "xray:PutTraceSegments",
         "xray:PutTelemetryRecords"
       ],
       Resource = "*"
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


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
 role       = aws_iam_role.lambda_exec_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}"
 repository = var.github_repo
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
         - aws s3 sync build/ s3://\$BUCKET_NAME
 artifacts:
   baseDirectory: /build
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

output "cognito_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
 value = aws_apigatewayv2_api.main.id
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}
