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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The name of the application."
  default     = "todo-app"
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }


  mfa_configuration = "OFF" # Consider changing to "ON" for production

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev" # Example
    Project     = "todo-app" # Example
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-domain"
    Environment = "dev" # Example
    Project     = "todo-app" # Example
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Replace with your frontend callback URL
  logout_urls                         = ["http://localhost:3000/"] # Replace with your frontend logout URL
 prevent_user_existence_errors = "ENABLED"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = "dev" # Example
    Project     = "todo-app" # Example
  }
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Consider using PAY_PER_REQUEST for cost optimization
  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "dev" # Example
    Project     = "todo-app" # Example
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
    Environment = "dev"
    Project     = "todo-app"
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
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
 tags = {
    Name        = "api-gateway-cloudwatch-policy-${var.stack_name}"
    Environment = "dev"
    Project     = "todo-app"
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
 minimum_compression_size = 0
 tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = "dev"
    Project     = "todo-app"
  }
}



resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role-${var.stack_name}"

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
    Name        = "lambda-execution-role-${var.stack_name}"
    Environment = "dev"
    Project     = "todo-app"
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy-${var.stack_name}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
 "dynamodb:Query",
          "dynamodb:Scan",
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },      {
        Action = [
 "cloudwatch:PutMetricData"
        ],
        Effect = "Allow",
 Resource = "*"
      },
      {
 Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Effect = "Allow",
 Resource = "*"
      }
    ]
  })
 tags = {
    Name        = "lambda-dynamodb-policy-${var.stack_name}"
    Environment = "dev"
    Project     = "todo-app"
  }
}



resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


resource "aws_lambda_function" "add_item_function" {
 filename      = "../lambda/addItem.zip" # Replace with your lambda function zip file
  function_name = "add-item-function-${var.stack_name}"
  role          = aws_iam_role.lambda_execution_role.arn
 handler = "index.handler"
  runtime = "nodejs16.x" # Updated runtime for security
 memory_size = 1024
  timeout = 60
  tracing_config {
 mode = "Active"
  }
 tags = {
    Name        = "add-item-function-${var.stack_name}"
    Environment = "dev"
    Project     = "todo-app"
  }

}


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
EOF
 tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = "dev"
    Project     = "todo-app"
  }

}


resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
 enable_auto_build = true
 tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-branch"
    Environment = "dev"
    Project     = "todo-app"
  }

}



output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}


output "api_gateway_id" {
 value       = aws_api_gateway_rest_api.main.id
  description = "The ID of the API Gateway."
}


output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify App."
}


