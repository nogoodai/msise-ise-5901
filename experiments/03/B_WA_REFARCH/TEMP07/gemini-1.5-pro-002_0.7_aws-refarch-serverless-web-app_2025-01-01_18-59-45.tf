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
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  allowed_oauth_flows                  = ["implicit", "authorization_code"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  generate_secret                     = false
  callback_urls = ["http://localhost:3000/"] # Placeholder, update with your callback URL
  logout_urls  = ["http://localhost:3000/"] # Placeholder, update with your logout URL
  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


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

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
}


resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito_authorizer"
  rest_api_id    = aws_api_gateway_rest_api.main.id
  provider_arns  = [aws_cognito_user_pool.main.arn]
  type           = "COGNITO_USER_POOLS"
 authorizer_uri = aws_cognito_user_pool_domain.main.domain
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api_gateway_cloudwatch_role_${var.stack_name}"

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
 name = "api_gateway_cloudwatch_policy_${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

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
      },
    ]
 })
}

resource "aws_amplify_app" "main" {
 name      = "${var.application_name}-${var.stack_name}-amplify"
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
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF
}


resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-bucket"
}

resource "aws_iam_role" "amplify_role" {
  name = "amplify_role_${var.stack_name}"
  assume_role_policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
 {
 Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "amplify.amazonaws.com"
 }
      },
    ]
  })
}



resource "aws_iam_role_policy" "amplify_policy" {
  name = "amplify_policy_${var.stack_name}"
  role = aws_iam_role.amplify_role.id

  policy = jsonencode({
    Version = "2012-10-17",
 Statement = [
 {
 Effect = "Allow",
        Action = [
 "amplify:*"
 ],
 Resource = "*"
 }
    ]
  })
}


resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true
}



# Placeholder lambda functions - replace with your actual lambda code
resource "aws_lambda_function" "add_item" {
  function_name = "add_item_${var.stack_name}"
  # ... other configuration ...
}

# ... other lambda functions ...

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
  value = aws_api_gateway_deployment.main.invoke_url # Requires creating a deployment resource
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}


