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
  name              = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id      = aws_cognito_user_pool.main.id
  generate_secret   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Placeholder, replace with your actual callback URLs
  logout_urls                          = ["http://localhost:3000/"] # Placeholder, replace with your actual logout URLs
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
          "logs:PutLogEvents",
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}

resource "aws_apigatewayv2_api" "main" {
  name          = "serverless-todo-api-${var.stack_name}"
  protocol_type = "HTTP"
}


resource "aws_amplify_app" "main" {
 name             = "${var.application_name}-${var.stack_name}"
 repository       = var.github_repo_url
 access_token     = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token
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
         - aws s3 sync build s3://${aws_s3_bucket.main.bucket}/
 artifacts:
   baseDirectory: build
   files:
     - '**/*'
EOF
}


resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-bucket"
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}


# Placeholder lambda function resource (adapt as needed for your specific lambda functions)
resource "aws_lambda_function" "example" {
  function_name = "example-${var.stack_name}"
  handler = "index.handler"
 runtime = "nodejs12.x"
  memory_size = 1024
  timeout = 60
  tracing_config {
 mode = "Active"
  }
 role = aws_iam_role.lambda_exec_role.arn

#  Replace with your actual Lambda function code
 source_path = "./lambda_function_code/" # Placeholder
}


resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" # Adjust policy as needed
  role       = aws_iam_role.lambda_exec_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
  role       = aws_iam_role.lambda_exec_role.name
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
