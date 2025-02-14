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
  type        = string
  default     = "us-east-1"
  description = "The AWS region to deploy the resources to."
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack."
}

variable "application_name" {
  type        = string
  default     = "todo-app"
  description = "The application Name."
}

variable "github_repo" {
  type        = string
 description = "Github repository for the application"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "Github branch for the application"
}

variable "github_token" {
  type        = string
  description = "Github token for accessing the repository"
  sensitive   = true

}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  mfa_configuration = "OFF" # Explicitly set MFA to OFF

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_SRP_AUTH"]
  generate_secret     = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Placeholder, replace with your actual callback URLs
  logout_urls          = ["http://localhost:3000/"] # Placeholder, replace with your actual logout URLs
  supported_identity_providers = ["COGNITO"]


  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = "dev"
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


 point_in_time_recovery {
    enabled = true
  }


  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "dev"
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
    Environment = "dev"
    Project     = var.application_name
  }
}


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

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
      },
    ]
  })

  tags = {
    Name        = "api-gateway-cloudwatch-policy-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}




resource "aws_apigatewayv2_api" "main" {
 name = "serverless-todo-api-${var.stack_name}"
  protocol_type = "HTTP"

  tags = {
    Name        = "serverless-todo-api-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}



resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo
  access_token = var.github_token
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
  postBuild:
    commands:
      - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
artifacts:
  baseDirectory: /
  files:
    - '**/*'
EOF
 tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }

}


resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-amplify-bucket-${var.stack_name}"
  acl    = "private"
 force_destroy = true

  logging {
    target_bucket = "s3-access-logs-${var.application_name}-amplify-bucket-${var.stack_name}" # Replace with an existing log bucket name
    target_prefix = "log/"
  }

 versioning {
    enabled = true
  }

  tags = {
    Name        = "${var.application_name}-amplify-bucket-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }


}



resource "aws_s3_bucket" "log_bucket" {
  bucket = "s3-access-logs-${var.application_name}-amplify-bucket-${var.stack_name}" # Replace with a unique and descriptive name
  acl    = "log-delivery-write"
 force_destroy = true
  lifecycle_rule {
    id = "log"
    enabled = true
    noncurrent_version_expiration {
      days = 30
    }
    expiration {
      days = 90
    }

  }

  tags = {
    Name        = "s3-access-logs-${var.application_name}-amplify-bucket-${var.stack_name}"
    Environment = "log"
    Project     = "log-bucket"
  }


}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true


  tags = {
    Name        = "${var.application_name}-amplify-branch-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamodb-policy-${var.stack_name}"

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
 "dynamodb:Query",
          "dynamodb:Scan",
        ],
        Resource = aws_dynamodb_table.main.arn
      },
    ]
  })
tags = {
    Name        = "lambda-dynamodb-policy-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name = "lambda-cloudwatch-policy-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
 "logs:CreateLogStream",
          "logs:PutLogEvents",
 "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      },
    ]
  })
tags = {
    Name        = "lambda-cloudwatch-policy-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
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

output "api_gateway_url" {
 value = aws_apigatewayv2_api.main.api_endpoint
 description = "The URL of the API Gateway"
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify App."
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
 description = "The default domain of the Amplify App."
}


