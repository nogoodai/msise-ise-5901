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
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type = string
}

variable "application_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}"

  email_verification_message = "Your verification code is: {####}"
  mfa_configuration         = "OFF"
  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
    require_uppercase = true
    temporary_password_validity_days = 7
  }
  schema {
    attribute = "email"
    mutable   = true
    name      = "email"
    required  = true
  }
  username_attributes = ["email"]
  verification_attribute_update_settings {
    default_email_option = "CONFIRM_WITH_CODE"
  }
 tags = {
    Name        = "${var.application_name}-${var.stack_name}-cognito-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-client"
  user_pool_id                        = aws_cognito_user_pool.main.id
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Update with your actual callback URLs
  generate_secret                     = false
  prevent_user_existence_errors = "ENABLED"
  refresh_token_validity = 30
  supported_identity_providers        = ["COGNITO"]
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]


  tags = {
    Name        = "${var.application_name}-${var.stack_name}-cognito-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }

}


resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}




resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 point_in_time_recovery {
    enabled = true
  }
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }

  hash_key  = "cognito-username"
  range_key = "id"

 server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}





resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-${var.stack_name}"

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
    Name        = "api-gateway-cloudwatch-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }

}


resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-${var.stack_name}"


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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
 policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
}


resource "aws_apigatewayv2_api" "main" {
  name          = "${var.application_name}-${var.stack_name}-api"
  protocol_type = "HTTP"
 cors_configuration {
    allow_headers = ["content-type", "x-api-key", "x-amzn-trace-id", "Authorization"]
    allow_methods = ["OPTIONS", "GET", "POST", "PUT", "PATCH", "DELETE"]
    allow_origins = ["*"]
  }
  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name         = "prod"
  auto_deploy = true

 access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({
      requestId       = "$context.requestId",
      ip             = "$context.identity.sourceIp",
 routeKey        = "$context.routeKey",
      status         = "$context.status",
      protocol       = "$context.protocol",
      responseLength = "$context.responseLength",
      integrationLatency = "$context.integrationLatency"

    })
  }
}

resource "aws_cloudwatch_log_group" "api_gw" {
 name = "/aws/apigateway/${aws_apigatewayv2_api.main.name}/access_logs"
 retention_in_days = 30

}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_source  = ["$auth.jwtAuthorizer.claims.sub"]
  jwt_configuration {
 audience         = [aws_cognito_user_pool_client.main.id]
    issuer          = aws_cognito_user_pool.main.issuer_url
  }
  name = "cognito_authorizer"
}



resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role_${var.stack_name}"

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
}


resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda_dynamodb_policy_${var.stack_name}"
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
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
 "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem",


        ],
        Resource = aws_dynamodb_table.todo_table.arn

      },
      {
        Effect = "Allow",
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },      
      {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
  role       = aws_iam_role.lambda_exec_role.name
}


# Placeholder for Lambda functions - replace with your actual Lambda function code and deployment mechanism.
# The following resource blocks demonstrate how to define Lambda functions with necessary configurations.

resource "aws_lambda_function" "example_lambda" {
  filename      = "lambda_function.zip" # Replace with your Lambda function zip file
  function_name = "example-lambda-${var.stack_name}"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.handler" # Replace with your Lambda function handler
  runtime = "nodejs16.x" # Or another supported runtime
 memory_size = 1024
  timeout = 60
 tracing_config {
    mode = "Active"
  }


  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }


  tags = {
    Name        = "example-lambda-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
 repository = var.github_repo_url
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with a secure method to manage secrets

 build_spec = jsonencode({
    version = 0.1,
    frontend = {
      phases = {
        preBuild  = "npm ci",
        build     = "npm run build",
        postBuild = "npm run deploy"
      },
 artifacts = {
        baseDirectory = "/build",
 files = ["**/*"]
      }
    }
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.application_name
  }

}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

}




output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


