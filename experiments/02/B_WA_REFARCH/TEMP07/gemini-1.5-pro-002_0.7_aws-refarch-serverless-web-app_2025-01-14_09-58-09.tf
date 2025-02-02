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
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/"] # Placeholder, replace with actual callback URL
  logout_urls                          = ["http://localhost:3000/"] # Placeholder, replace with actual logout URL
  supported_identity_providers         = ["COGNITO"]

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
 enabled     = true
    kms_key_id = "alias/aws/dynamodb"
  }
 tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "api_gateway_cw_role" {
 name = "api-gateway-cw-role-${var.stack_name}"

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



resource "aws_iam_role_policy" "api_gateway_cw_policy" {
  name = "api-gateway-cw-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_role.id

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

resource "aws_iam_role" "lambda_dynamodb_role" {
  name = "lambda-dynamodb-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
 Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
 Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
 name = "lambda-dynamodb-policy-${var.stack_name}"
 role = aws_iam_role.lambda_dynamodb_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
 "dynamodb:Scan",
 "dynamodb:Query",
 "dynamodb:BatchGetItem",
 "dynamodb:BatchWriteItem"
 ],
 Resource = aws_dynamodb_table.main.arn,
 Effect = "Allow"
 },
 {
 Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
 ],
 Resource = "arn:aws:logs:*:*:*",
 Effect = "Allow"
      },
 {
 Action = [
 "xray:PutTraceSegments",
 "xray:PutTelemetryRecords"
 ],
 Resource = "*",
 Effect = "Allow"
      }
    ]
 })
}

# Placeholder for Lambda functions.  Lambda functions should be created as separate resources and referenced here.
# Example:
# resource "aws_lambda_function" "add_item_function" { ... }
# resource "aws_lambda_function" "get_item_function" { ... }
# ...


# Placeholder for API Gateway resources. API Gateway should be configured with appropriate methods, integrations, and authorizers.
# Example:
# resource "aws_api_gateway_rest_api" "main" { ... }
# resource "aws_api_gateway_resource" "item_resource" { ... }
# resource "aws_api_gateway_method" "post_item_method" { ... }
# ...

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url
  access_token = var.github_access_token

 build_spec = jsonencode({
 version = 0.1
 artifacts = ["build/**"]
 frontend = {
 phases = {
 preBuild = "npm install",
 build = "npm run build"
 }
 artifacts = {
 baseDirectory = "build"
 files = ["**/*"]
 }
 cache = {
 paths = [
 "node_modules/**/*"
 ]
      }
    }
  })
}

resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
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

# Placeholder for other outputs, such as API Gateway endpoint URL.
# Example:
# output "api_gateway_invoke_url" { ... }



