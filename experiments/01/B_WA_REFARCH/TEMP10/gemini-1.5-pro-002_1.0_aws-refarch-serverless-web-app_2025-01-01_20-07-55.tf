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

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-userpool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-userpool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-userpool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_CUSTOM_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["phone", "email", "openid"]

  callback_urls = ["http://localhost:3000/"] # Placeholder URL, replace with your actual URL


  tags = {
    Name        = "${var.application_name}-${var.stack_name}-userpool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-userpool-domain"
    Environment = var.stack_name
    Project     = var.application_name
  }
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }

}



resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF


  tags = {
    Name        = "api-gateway-cloudwatch-logs-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
 name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs_role.id

 policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
 {
 "Effect": "Allow",
 "Action": [
  "logs:CreateLogGroup",
  "logs:CreateLogStream",
  "logs:PutLogEvents"
 ],
 "Resource": "*"
 }
    ]
 })


}



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"

 description = "API Gateway for ${var.application_name}"

 tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }

}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify"
  repository = var.github_repo
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
    baseDirectory: build
    files:
      - '**/*'
  environment:
    REACT_APP_API_URL: $REACT_APP_API_URL
EOF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-branch"
    Environment = var.stack_name
    Project     = var.application_name
  }
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


