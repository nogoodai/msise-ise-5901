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

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}



# Cognito User Pool
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

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000/"] # Replace with actual callback URL
  logout_urls                          = ["http://localhost:3000/"] # Replace with actual logout URL

  supported_identity_providers = ["COGNITO"]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "cognito-username"
  range_key       = "id"
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
    Project     = var.application_name
  }
}



# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-role"

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

# IAM Policy for Lambda functions to access DynamoDB and CloudWatch
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.application_name}-${var.stack_name}-lambda-policy"
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
          "logs:PutLogEvents",
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



# Attach IAM policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# Lambda functions (replace with your actual function code)
resource "aws_lambda_function" "add_item" {
  function_name = "${var.application_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
 memory_size = 1024
  timeout        = 60

  role    = aws_iam_role.lambda_role.arn
  # Replace with your actual function code
  filename         = "add_item.zip"
  source_code_hash = filebase64sha256("add_item.zip")

  tracing_config {
 mode = "Active"
  }

 tags = {
    Name        = "${var.application_name}-${var.stack_name}-add-item"
    Environment = "prod"
    Project     = var.application_name
  }
}
# ... (other Lambda functions similarly)

# API Gateway (simplified - detailed configuration depends on your API design)
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.application_name}-${var.stack_name}-api"
  protocol_type = "HTTP"
}

# API Gateway Integration (example for add_item function)
resource "aws_apigatewayv2_integration" "add_item" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "aws_proxy"
  integration_uri    = aws_lambda_function.add_item.invoke_arn
  integration_method = "POST"
}
# ... (other API Gateway Integrations similarly)




# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url
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
  cache:
    paths:
      - node_modules/**/*
EOF

}



# Amplify Branch
resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
 enable_auto_build = true

}


# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name = "${var.application_name}-${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
      {
 Action = "sts:AssumeRole",
 Principal = {
 Service = "amplify.amazonaws.com"
 },
 Effect = "Allow",
        Sid    = ""
 }
    ]
  })
}



# IAM Policy for Amplify
resource "aws_iam_policy" "amplify_policy" {

  name        = "${var.application_name}-${var.stack_name}-amplify-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
 Action = [
          "*:Create*",
          "*:Update*",
          "*:Delete*",
          "*:Read*",
 "*:Get*"

 ],
        Resource = "*"
      }
    ]

  })
}

# Attach IAM policy to Amplify role
resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
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

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}



