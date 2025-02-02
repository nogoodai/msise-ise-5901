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
  type = string
}

variable "application_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  schema {
    attribute_data_type = "String"
    developer_only_attribute = false
    mutable = true
    name = "email"
    required = true

  }

  username_attributes = ["email"]
  verification_message_template {
    default_email_options {
      delivery_failure_handler = "OPTIMIZED"
    }
    email_message = "Your verification code is {####}"
    email_message_by_link = "Your verification link is {##Click Here##}"
    email_subject = "Welcome to ${var.application_name}"
    email_subject_by_link = "Verify your email for ${var.application_name}"
    sms_message = "Your verification code is {####}"
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }

}


resource "aws_cognito_user_pool_client" "client" {
  name = "${var.application_name}-${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.main.id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Placeholder, update as needed
  generate_secret                     = false

  prevent_user_existence_errors = "ENABLED"

  supported_identity_providers = ["COGNITO"]
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_dynamodb_table" "todo_table" {
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



resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

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

  tags = {
    Name        = "api-gateway-cloudwatch-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
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

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
 policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
 role       = aws_iam_role.api_gateway_cloudwatch_role.name

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
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with an access token or use a secrets management solution
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

 tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_amplify_branch" "main" {

 app_id      = aws_amplify_app.main.id
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
  value = aws_cognito_user_pool_client.client.id
}

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}

