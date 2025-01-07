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

variable "github_repo_url" {
  type    = string
  default = "https://github.com/example/todo-app" # Replace with your GitHub repository URL
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Replace with your callback URLs
  logout_urls         = ["http://localhost:3000/"] # Replace with your logout URLs
  supported_identity_providers = ["COGNITO"]

  prevent_user_existence_errors = "ENABLED"
}



# DynamoDB Table
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


# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
 name = "${var.stack_name}-lambda-role"
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

resource "aws_iam_policy" "lambda_policy" {
  name = "${var.stack_name}-lambda-policy"
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
 "dynamodb:Query"
        ],
        Resource = aws_dynamodb_table.main.arn,
        Effect   = "Allow"
      },

      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*",
        Effect   = "Allow"
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

resource "aws_iam_role_policy_attachment" "lambda_attach" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda Functions (Placeholder - Replace with your actual Lambda code)
resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler" # Replace with your handler
 runtime = "nodejs12.x"
  memory_size = 1024
 timeout = 60
 role = aws_iam_role.lambda_role.arn
 tracing_config {
 mode = "Active"
 }
 # Replace with your Lambda code
 source_path = "../../lambda/add-item" # Example path
}
# ... similar resources for get_item, get_all_items, update_item, complete_item, delete_item ...

# API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"

}

# ... resources for API Gateway methods, integrations, authorizer, stages, usage plan ...

# Amplify App

resource "aws_amplify_app" "main" {
 name = var.stack_name
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token
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
resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true
}

# IAM Role for API Gateway CloudWatch Logs
resource "aws_iam_role" "api_gateway_cw_role" {
  name = "${var.stack_name}-apigw-cw-role"
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
      }
    ]
  })
}

# IAM Policy for API Gateway CloudWatch Logs
resource "aws_iam_policy" "api_gateway_cw_policy" {

  name = "${var.stack_name}-apigw-cw-policy"
 policy = jsonencode({
 Version = "2012-10-17",
 Statement = [
 {
 Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:DescribeLogGroups",
 "logs:DescribeLogStreams",
 "logs:PutLogEvents",
 "logs:GetLogEvents",
 "logs:FilterLogEvents"
 ],
 Resource = "*",
 Effect = "Allow"
 }
 ]
 })

}

# Attach policy to role

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
 role       = aws_iam_role.api_gateway_cw_role.name
 policy_arn = aws_iam_policy.api_gateway_cw_policy.arn
}




# Outputs

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

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}
