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

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
  default     = "your-github-repo"
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 8
    require_lowercase = true
    require_numbers  = true
    require_symbols  = true
    require_uppercase = true
  }

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  mfa_configuration = "OFF" # Consider enforcing MFA


  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod" # Example
    Project     = "todo-app" # Example

  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.stack_name}-user-pool-domain"
    Environment = "prod" # Example
    Project     = "todo-app" # Example

  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  generate_secret = false

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod" # Example
    Project     = "todo-app" # Example
  }

  # Prevent sensitive data exposure
  prevent_user_existence_errors = "ENABLED"
}

resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PAY_PER_REQUEST" # Use on-demand billing for cost optimization
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
    Environment = "prod" # Example
    Project     = "todo-app" # Example

  }


}




resource "aws_apigatewayv2_api" "main" {
  name          = "${var.stack_name}-api"
  protocol_type = "HTTP"

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod" # Example
    Project     = "todo-app" # Example
  }
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name         = "prod"
  auto_deploy = true



 access_log_settings {
    destination_arn = data.aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({
      requestId = "$context.requestId",
      ip        = "$context.identity.sourceIp",
      requestTime = "$context.requestTime",
      httpMethod = "$context.httpMethod",
      routeKey = "$context.routeKey",
      status = "$context.status",
      protocol = "$context.protocol",
      responseLength = "$context.responseLength",
    })
  }

  default_route_settings {
    data_trace_enabled = true
    detailed_metrics_enabled = true
    logging_level = "INFO"
  }
  tags = {
    Name        = "${var.stack_name}-api-stage"
    Environment = "prod" # Example
    Project     = "todo-app" # Example
  }
}

data "aws_cloudwatch_log_group" "api_gw" {
  name_prefix = "/aws/apigateway/${aws_apigatewayv2_api.main.name}/access_logs"
}



resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "COGNITO_USER_POOLS"
  name             = "cognito_authorizer"
  identity_source = ["$request.header.Authorization"]
  provider_arns    = [aws_cognito_user_pool.main.arn]

  tags = {
    Name        = "${var.stack_name}-api-authorizer"
    Environment = "prod" # Example
    Project     = "todo-app" # Example
  }
}


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
    Environment = "prod" # Example
    Project     = "todo-app" # Example
  }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.stack_name}-lambda-dynamodb-policy"
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
 ],
        Effect = "Allow",
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
    Name        = "${var.stack_name}-lambda-dynamodb-policy"
    Environment = "prod" # Example
    Project     = "todo-app" # Example

  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo

 build_spec = <<-EOT
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
     baseDirectory: /build
     files:
       - '**/*'
   cache:
     paths:
       - node_modules/**/*
 EOT

  tags = {
    Name        = var.stack_name
    Environment = "prod" # Example
    Project     = "todo-app" # Example

  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

  tags = {
    Name        = "${var.stack_name}-amplify-branch"
    Environment = "prod" # Example
    Project     = "todo-app" # Example
  }
}


resource "aws_accessanalyzer_analyzer" "analyzer" {
  analyzer_name = "example"
  type          = "ACCOUNT"

  tags = {
    Name = "example"
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
  description = "The ID of the Amplify App."
}
