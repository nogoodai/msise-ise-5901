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

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}




resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }

}



resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]


  generate_secret = false

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
    Project     = var.stack_name
  }
}



resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.stack_name}-${random_id.main.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "random_id" "main" {
  byte_length = 8
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}


resource "aws_iam_role" "api_gateway_cw_role" {
  name = "${var.stack_name}-api-gateway-cw-role"

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
    Name        = "${var.stack_name}-api-gateway-cw-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}


resource "aws_iam_role_policy" "api_gateway_cw_policy" {
 name = "${var.stack_name}-api-gateway-cw-policy"
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
      }
    ]
  })
}



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = var.stack_name
  }

}



resource "aws_lambda_function" "add_item" { # Example Lambda function - repeat for others
 filename      = "add_item.zip" # Placeholder, replace with your actual zip file
  function_name = "${var.stack_name}-add-item"
  role          = aws_iam_role.lambda_dynamodb_role.arn
  handler       = "index.handler" # Placeholder, replace with your actual handler
  source_code_hash = filebase64sha256("add_item.zip")
  runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60
  tracing_config {
 mode = "Active"
  }

  environment {
 variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-add-item-lambda"
    Environment = "prod"
    Project     = var.stack_name
  }
}


resource "aws_iam_role" "lambda_dynamodb_role" {
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
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-dynamodb-role"
    Environment = "prod"
    Project     = var.stack_name
 }
}

resource "aws_iam_role_policy" "lambda_dynamodb_policy" { # Example policy - modify and repeat for other functions
  name = "${var.stack_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_dynamodb_role.id

  policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
 Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
 "dynamodb:Scan" # Add Scan if needed
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



resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo
  build_spec = <<EOF
version: 0.1
frontend:
 phases:
    preBuild:
      commands:
        - yarn install
    build:
 commands:
        - yarn build
  artifacts:
    baseDirectory: /
    files:
 - '**/*'
  cache:
 paths:
      - node_modules/**/*
EOF


  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = "prod"
    Project     = var.stack_name
  }


}

resource "aws_amplify_branch" "master" {
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

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}


output "amplify_app_id" {
 value = aws_amplify_app.main.id
}


