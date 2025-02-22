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
  description = "The AWS region to deploy the resources to."
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The application Name"
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

resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  mfa_configuration = "OFF" # Added MFA configuration

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "dev"
    Project     = "todo-app"

  }
}



resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity = 5
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

 point_in_time_recovery {
    enabled = true
 }

  tags = {
    Name = "todo-table-${var.stack_name}"
    Environment = "dev"
    Project = "todo-app"
  }

}

resource "aws_iam_role" "api_gateway_cw_logs" {
  name = "api-gateway-cw-logs-${var.stack_name}"

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
    Name = "api-gateway-cw-logs-${var.stack_name}"
    Environment = "dev"
    Project = "todo-app"
  }
}

resource "aws_iam_role_policy" "api_gateway_cw_logs" {
 name = "api-gateway-cw-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_logs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ],
        Effect = "Allow",
        Resource = "*"
      },
    ]
  })

}

resource "aws_api_gateway_rest_api" "main" {
  name        = "todo-api-${var.stack_name}"
 minimum_compression_size = 0

 tags = {
    Name = "todo-api-${var.stack_name}"
    Environment = "dev"
    Project = "todo-app"
  }


}


resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role-${var.stack_name}"

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
      }
    ]
  })

  tags = {
    Name = "lambda-exec-role-${var.stack_name}"
    Environment = "dev"
    Project = "todo-app"
  }
}

resource "aws_iam_policy" "lambda_dynamodb" {
  name        = "lambda-dynamodb-policy-${var.stack_name}"
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
        Effect = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
    ]
  })

  tags = {
    Name = "lambda-dynamodb-policy-${var.stack_name}"
    Environment = "dev"
    Project = "todo-app"

  }
}


resource "aws_iam_policy_attachment" "lambda_dynamodb_attach" {
  name       = "lambda-dynamodb-attach-${var.stack_name}"
  roles      = [aws_iam_role.lambda_exec.name]
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}


resource "aws_iam_policy" "lambda_cw_metrics" {
  name = "lambda-cw-metrics-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
 "cloudwatch:PutMetricData",
        ],
        Effect = "Allow",
 Resource = "*"
      },
    ]
  })

  tags = {
    Name = "lambda-cw-metrics-${var.stack_name}"
        Environment = "dev"
    Project = "todo-app"
  }

}


resource "aws_iam_policy_attachment" "lambda_cw_metrics_attach" {
  name       = "lambda-cw-metrics-${var.stack_name}"
  roles      = [aws_iam_role.lambda_exec.name]
  policy_arn = aws_iam_policy.lambda_cw_metrics.arn
}



resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
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
   baseDirectory: /
   files:
     - '**/*'
EOF

}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
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
 value = aws_api_gateway_rest_api.main.id
 description = "The ID of the API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify App."
}

