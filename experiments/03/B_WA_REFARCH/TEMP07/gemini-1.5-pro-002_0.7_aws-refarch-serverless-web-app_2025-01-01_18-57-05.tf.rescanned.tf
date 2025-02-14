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
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack. Used for naming resources."
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository to use."
  default     = "master"
}

variable "github_access_token" {
  type        = string
  description = "Personal Access Token for GitHub."
  sensitive   = true

}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"
  sms_configuration {
    external_id = "example" # Replace with your external ID
    sns_caller_arn = "arn:aws:iam::xxxxxxxxxxxx:role/example" # Replace with SNS caller ARN

  }
 tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production" # Example
    Project     = "todo-app" # Example
  }


}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id


  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code"]
  allowed_oauth_scopes                = ["email", "openid"]

  generate_secret = false

  prevent_user_existence_errors = "ENABLED" # Prevent user existence errors during OAuth flows

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "production"
    Project     = "todo-app"
  }


}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain      = "${var.stack_name}-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.main.id
 tags = {
    Name        = "${var.stack_name}-user-pool-domain"
    Environment = "production"
    Project     = "todo-app"
  }

}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST"
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

  point_in_time_recovery {
    enabled = true
  }

 server_side_encryption {
    enabled = true
  }
    tags = {
    Name        = "todo-table-${var.stack_name}"
        Environment = "production"
        Project     = "todo-app"
  }

}



# IAM Role for API Gateway logging
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
    Environment = "production"
    Project     = "todo-app"
  }
}

# IAM Policy for API Gateway logging
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
 tags = {
    Name        = "api-gateway-cloudwatch-policy-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Attach IAM Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}




# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"

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
    Name        = "lambda-role-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

# IAM Policy for Lambda DynamoDB access
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
"dynamodb:Query",
"dynamodb:DescribeTable"


        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Effect = "Allow",
        Resource = "*"

      }
    ]
  })

 tags = {
    Name        = "lambda-dynamodb-policy-${var.stack_name}"
    Environment = "production"
    Project     = "todo-app"
  }
}

# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


# Amplify App
resource "aws_amplify_app" "main" {
  name         = var.stack_name
  repository   = var.github_repo
  access_token = var.github_access_token
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
    baseDirectory: /build
    files:
      - '**/*'
EOF
 tags = {
    Name        = var.stack_name
    Environment = "production"
    Project     = "todo-app"
  }
}




# Amplify Branch
resource "aws_amplify_branch" "master" {
  app_id         = aws_amplify_app.main.id
  branch_name    = var.github_branch
  enable_auto_build = true
  tags = {
    Name        = var.github_branch
    Environment = "production"
    Project     = "todo-app"
  }
}



# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "cognito_user_pool_domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "The domain of the Cognito User Pool."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify App."
}

output "amplify_default_domain" {
  value       = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify App."
}

resource "aws_accessanalyzer_analyzer" "example" {
  analyzer_name = "example"
  tags = {
    Name = "example"

  }
 type = "ACCOUNT"
}


