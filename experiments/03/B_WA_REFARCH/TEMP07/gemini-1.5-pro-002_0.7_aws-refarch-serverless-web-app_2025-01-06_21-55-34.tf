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
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email address"

  password_policy {
    minimum_length                  = 6
    require_lowercase              = true
    require_numbers                = false
    require_symbols                = false
    require_uppercase              = true
    temporary_password_validity_days = 7
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.stack_name}-cognito-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.stack_name}-auth"
 user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.stack_name}-app-client"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]

  callback_urls = ["http://localhost:3000/"] # Replace with your actual callback URLs
  logout_urls   = ["http://localhost:3000/"] # Replace with your actual logout URLs

  tags = {
    Name        = "${var.stack_name}-cognito-user-pool-client"
    Environment = "prod"
    Project     = var.stack_name
  }
}



# DynamoDB Table
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
    Name        = "${var.stack_name}-dynamodb-table"
    Environment = "prod"
    Project     = var.stack_name
 }
}


# IAM Role for API Gateway to write CloudWatch logs
resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "${var.stack_name}-api-gateway-cloudwatch-logs-role"

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
    Name        = "${var.stack_name}-api-gateway-cw-logs-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# IAM Policy for API Gateway to write CloudWatch logs
resource "aws_iam_policy" "api_gateway_cloudwatch_logs_policy" {
 name = "${var.stack_name}-api-gateway-cloudwatch-logs-policy"

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


  tags = {
 Name        = "${var.stack_name}-api-gateway-cw-logs-policy"
 Environment = "prod"
 Project     = var.stack_name
 }
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs_attachment" {
 policy_arn = aws_iam_policy.api_gateway_cloudwatch_logs_policy.arn
  role       = aws_iam_role.api_gateway_cloudwatch_logs_role.name
}




# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
 name = "${var.stack_name}-lambda-role"

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
    Name        = "${var.stack_name}-lambda-role"
 Environment = "prod"
 Project     = var.stack_name
  }
}

# IAM Policy for Lambda to access DynamoDB and CloudWatch
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
        Effect   = "Allow",
 Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
 "cloudwatch:PutMetricData"
 ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
 Effect   = "Allow",
 Resource = "*"
      }


    ]
 })


  tags = {
    Name        = "${var.stack_name}-lambda-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "lambda_attachment" {
  policy_arn = aws_iam_policy.lambda_policy.arn
  role       = aws_iam_role.lambda_role.name
}



# Placeholder for Lambda functions - replace with actual implementation
resource "aws_lambda_function" "example_lambda" {
  function_name = "${var.stack_name}-lambda-function"
  handler       = "index.handler" # Replace with your handler
 runtime      = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60

  role    = aws_iam_role.lambda_role.arn


 source_code_hash = filebase64sha256("lambda_function_zip.zip") # Replace with your Lambda's source code
  filename         = "lambda_function_zip.zip"

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-lambda-function"
    Environment = "prod"
    Project     = var.stack_name
  }
}


# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
 description = "API Gateway for ${var.stack_name}"

 tags = {
 Name        = "${var.stack_name}-api-gateway"
    Environment = "prod"
    Project     = var.stack_name
  }
}


# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 stage_name  = "prod"

 depends_on = [
    # Ensure deployment happens after all resources are created
  ]


}


# Amplify App
resource "aws_amplify_app" "main" {
 name             = var.stack_name
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
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF


  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Amplify Branch - Auto Build enabled
resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true

 tags = {
    Name        = "${var.stack_name}-amplify-branch"
    Environment = "prod"
    Project     = var.stack_name
 }
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

output "api_gateway_invoke_url" {
 value = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}
