provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Configure Cognito User Pool
resource "aws_cognito_user_pool" "pool" {
  name             = "cognito-user-pool"
  alias_attributes = ["email"]

  email_configuration {
    email_sending_account = "amazon.com"
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
  }

  verification_message_template {
    email_message = ""
    email_subject = ""
  }

  tags = {
    Name        = "cognito-user-pool"
    Environment = "prod"
    Project     = "serverless-web-app"
  }
}

# Configure Cognito User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  name                = "cognito-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]

  allowed_oauth_flows_user_pool_client = true

  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Configure Cognito Domain
resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "auth.example.com"
  user_pool_id = aws_cognito_user_pool.pool.id
}

# Configure DynamoDB Table
resource "aws_dynamodb_table" "table" {
  name           = "todo-table-serverless-web-app"
  read_capacity_units  = 5
  write_capacity_units = 5
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

  tags = {
    Name        = "todo-table"
    Environment = "prod"
    Project     = "serverless-web-app"
  }

  server_side_encryption {
    enabled = true
  }
}

# Configure API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "serverless-web-app-api"
  description = "Serverless Web App API"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name        = "cognito-authorizer"
  rest_api_id = aws_api_gateway_rest_api.api.id
  provider_arns = [
    aws_cognito_user_pool.pool.arn,
  ]

  type = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_method.method]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "serverless-web-app-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }

  quota {
    limit  = 5000
    period = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

# Configure Lambda Functions
resource "aws_lambda_function" "lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "serverless-web-app-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.table.name
    }
  }
}

resource "aws_lambda_permission" "permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# Configure API Gateway Integration with Lambda
resource "aws_api_gateway_integration" "integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_region}:${aws_account_id}:function:${aws_lambda_function.lambda.function_name}/invocations"
}

# Configure Amplify App
resource "aws_amplify_app" "app" {
  name        = "serverless-web-app"
  description = "Serverless Web App"
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = "master"
}

# Configure IAM Roles and Policies
resource "aws_iam_role" "lambda_exec" {
  name        = "serverless-web-app-lambda-exec"
  description = "Serverless Web App Lambda Execution Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "serverless-web-app-lambda-policy"
  description = "Serverless Web App Lambda Policy"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "api_gateway_exec" {
  name        = "serverless-web-app-api-gateway-exec"
  description = "Serverless Web App API Gateway Execution Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "serverless-web-app-api-gateway-policy"
  description = "Serverless Web App API Gateway Policy"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_attach" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "serverless-web-app-amplify-exec"
  description = "Serverless Web App Amplify Execution Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "serverless-web-app-amplify-policy"
  description = "Serverless Web App Amplify Policy"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.app.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_attach" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.deployment.stage_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.lambda.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.branch.branch_name
}
