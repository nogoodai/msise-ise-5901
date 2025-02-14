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
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The application's name."
  default     = "todo-app"
}

variable "github_repo_url" {
  type        = string
  description = "URL of the GitHub repository."
}

variable "github_repo_branch" {
  type        = string
  description = "Branch of the GitHub repository."
  default     = "master"
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token with appropriate permissions."
  sensitive   = true
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
  mfa_configuration = "OFF" # Explicitly set MFA to OFF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  prevent_user_existence_errors = "ENABLED"

}

resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PAY_PER_REQUEST" # Use on-demand billing for better cost efficiency
  hash_key      = "cognito-username"
  range_key     = "id"


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

 point_in_time_recovery {
    enabled = true
 }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}




resource "aws_iam_role" "api_gateway_cw_role" {
  name = "api-gateway-cw-role-${var.stack_name}"

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
    Name        = "api-gateway-cw-role-${var.stack_name}"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}


resource "aws_iam_role_policy" "api_gateway_cw_policy" {
 name = "api-gateway-cw-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_role.id

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

# Lambda and API Gateway resources (simplified due to length constraints)
# ...

resource "aws_amplify_app" "main" {
  name         = "${var.application_name}-${var.stack_name}"
  repository   = var.github_repo_url
  access_token = var.github_access_token
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
    Name        = "${var.application_name}-${var.stack_name}"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true


  tags = {
    Name        = "${var.application_name}-${var.stack_name}-branch"
    Environment = "dev" # Replace with your environment
    Project     = var.application_name
  }
}

# IAM Roles and Policies for Lambda and Amplify (simplified)
# ...

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}


resource "aws_accessanalyzer_analyzer" "analyzer" {
  analyzer_name = "example"
  type          = "ACCOUNT"

  tags = {
    Name = "example"
  }
}


