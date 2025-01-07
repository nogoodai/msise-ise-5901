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

variable "github_repo" {
  type    = string
  default = "your-github-repo"
}

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 6
    require_lowercase                = true
    require_numbers                 = false
    require_symbols                 = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.stack_name}-user-pool-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                      = ["http://localhost:3000"] # Placeholder - replace with your app's callback URL
  logout_urls                        = ["http://localhost:3000"] # Placeholder - replace with your app's logout URL
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_id.main.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_id" "main" {
  byte_length = 4
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


resource "aws_api_gateway_rest_api" "main" {
 name = "${var.stack_name}-api"
}


resource "aws_amplify_app" "main" {
  name = var.stack_name
 repository = var.github_repo
  access_token = "your-github-access-token" # Replace with your Github Personal Access Token with appropriate permissions

  build_spec = <<EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm install
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

}




resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}





# Placeholder for Lambda functions and API Gateway integration - this will need to be expanded
# with actual Lambda function code and API Gateway resource/method definitions.





# IAM Roles and Policies


data "aws_iam_policy_document" "assume_role_api_gateway" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api_gateway_role" {
 name = "api-gateway-role-${var.stack_name}"
 assume_role_policy = data.aws_iam_policy_document.assume_role_api_gateway.json
}


data "aws_iam_policy_document" "api_gateway_cloudwatch_logs" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:log-group:/aws/apigateway/*"]
  }
}

resource "aws_iam_policy" "api_gateway_cloudwatch_logs" {
  name        = "api-gateway-cloudwatch-logs-${var.stack_name}"
  description = "Allows API Gateway to write logs to CloudWatch Logs."
  policy = data.aws_iam_policy_document.api_gateway_cloudwatch_logs.json

}


resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_logs.arn
}




resource "aws_iam_role" "amplify_role" {
  name               = "amplify-role-${var.stack_name}"
  assume_role_policy = data.aws_iam_policy_document.assume_role_amplify.json

}

data "aws_iam_policy_document" "assume_role_amplify" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
 identifiers = ["amplify.amazonaws.com"]
    }
  }
}



# Outputs


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
 value       = aws_dynamodb_table.main.name
}


output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


