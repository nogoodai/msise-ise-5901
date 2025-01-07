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

variable "github_repo" {
  type    = string
  default = "your-github-repo" # Replace with your GitHub repository
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls          = ["http://localhost:3000/"] # Replace with your logout URLs
  supported_identity_providers = ["COGNITO"]
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



# API Gateway and Lambda Resources (Placeholders - Implementation details needed for full configuration)
# Due to the complexity and variations in implementing API Gateway and Lambda functions,
# especially with integrations and specifics like Node.js code, this section will act
# as a guided template. Replace placeholders with actual implementations.

# Example for one Lambda function (others should be added as required)
resource "aws_lambda_function" "addItem" {
# ... (implementation details)
  function_name = "addItem-${var.stack_name}"
  handler = "index.handler" # Replace with your Lambda handler
  runtime = "nodejs12.x"
  memory_size = 1024
  timeout = 60
  # ... (other settings like environment variables, VPC configuration etc.)

# ... policies
}




# Amplify App
resource "aws_amplify_app" "main" {
 name = "${var.application_name}-${var.stack_name}"
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
  artifacts:
    baseDirectory: /dist # Replace with your dist directory
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
  enable_auto_build = true


 stage = "PRODUCTION"
}


# IAM Roles and Policies (Placeholders - Detailed policy definitions required)
# Please replace the placeholder JSON policies with specific permissions
# relevant to the actions and resources involved in your application.

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.stack_name}"

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
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
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
 value = aws_dynamodb_table.main.name
}



output "amplify_app_id" {
 value = aws_amplify_app.main.id
}
output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}

