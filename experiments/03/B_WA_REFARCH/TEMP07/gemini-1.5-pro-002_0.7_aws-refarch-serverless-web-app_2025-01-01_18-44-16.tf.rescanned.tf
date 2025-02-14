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

variable "github_personal_access_token" {
  type        = string
  description = "GitHub personal access token."
  sensitive   = true
}


resource "aws_cognito_user_pool" "main" {
  name                       = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes        = ["email"]
  auto_verified_attributes   = ["email"]
  mfa_configuration          = "OFF" # Consider enforcing MFA for enhanced security
  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

  password_policy {
    minimum_length     = 8 # Increased minimum length for better security
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true # Added requirement for numbers
    require_symbols   = true # Added requirement for symbols
    temporary_password_validity_days = 7 # Reduced temporary password validity
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                     = ["http://localhost:3000/"] # Placeholder - update as needed
  logout_urls                       = ["http://localhost:3000/"] # Placeholder - update as needed

    prevent_user_existence_errors = "ENABLED"

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Changed to on-demand billing mode
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
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_iam_role" "api_gateway_cw_logs_role" {
  name = "api-gateway-cw-logs-${var.stack_name}"

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

  tags = {
    Name        = "api-gateway-cw-logs-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_iam_role_policy" "api_gateway_cw_logs_policy" {
  name = "api-gateway-cw-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cw_logs_role.id

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
        Resource = aws_cloudwatch_log_group.api_gw.arn # Restrict resource to specific log group
      }
    ]
  })
    tags = {
    Name        = "api-gateway-cw-logs-policy-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_apigatewayv2_api" "main" {
  name          = "${var.application_name}-api-${var.stack_name}"
  protocol_type = "HTTP"

  tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "prod"
  auto_deploy = true

 access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId = "$context.requestId",
      ip        = "$context.identity.sourceIp",
      requestTime = "$context.requestTime",
      httpMethod = "$context.httpMethod",
      routeKey = "$context.routeKey",
      status = "$context.status",
      protocol = "$context.protocol",
      responseLength = "$context.responseLength"
    })
  }
  tags = {
    Name        = "prod-stage-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_cloudwatch_log_group" "api_gw" {
 name = "/aws/apigateway/${aws_apigatewayv2_api.main.name}"
  retention_in_days = 30
    kms_key_id = aws_kms_key.log_group_key.arn # Encrypt logs with KMS
  tags = {
    Name        = "/aws/apigateway/${aws_apigatewayv2_api.main.name}"
    Environment = "prod"
    Project     = var.application_name
  }

}


resource "aws_kms_key" "log_group_key" {
  description             = "KMS key for encrypting API Gateway logs"
  deletion_window_in_days = 7
  enable_key_rotation = true # Enable key rotation
 policy = data.aws_iam_policy_document.log_group_key_policy.json
}

data "aws_iam_policy_document" "log_group_key_policy" {
 statement {
    sid    = "Allow administration of the key"
    effect = "Allow"

    principals {
      type        = "AWS"
 identifiers = [data.aws_caller_identity.current.arn]
    }

    actions = [
      "kms:*"
    ]

 resources = ["*"]
  }
}

data "aws_caller_identity" "current" {}



resource "aws_iam_role" "lambda_exec_role" {
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
      },
    ]
  })

  tags = {
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "prod"
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
          "logs:PutLogEvents"
 ],
        Resource = "*" # Consider restricting this to specific log groups
 }
    ]
  })
 tags = {
    Name        = "lambda-dynamodb-policy-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}




resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo_url
  access_token = var.github_personal_access_token
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
  cache:
    paths:
      - node_modules/**/*
EOF

  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}

resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true


  tags = {
    Name        = "master-branch-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
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

output "api_gateway_url" {
  value       = aws_apigatewayv2_api.main.api_endpoint
  description = "The URL of the API Gateway."
}


output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}


