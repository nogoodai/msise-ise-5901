provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/example/todo-frontend"
  description = "The GitHub repository URL"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "The GitHub token"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The GitHub branch"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "todo_pool" {
  name                     = "${var.stack_name}-user-pool"
  email_verification_subject = "Your verification code"
  email_verification_message = "Your verification code is {####}."
  alias_attributes           = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
  mfa_configuration = "OFF"
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "todo_client" {
  name                   = "${var.stack_name}-user-pool-client"
  user_pool_id           = aws_cognito_user_pool.todo_pool.id
  generate_secret        = false
  allowed_oauth_flows    = ["authorization_code", "implicit"]
  allowed_oauth_scopes   = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
}

# Custom Domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "todo_domain" {
  domain               = "${var.stack_name}-auth"
  user_pool_id         = aws_cognito_user_pool.todo_pool.id
  certificate_arn      = aws_acm_certificate.todo_cert.arn
}

# ACM Certificate for Custom Domain
resource "aws_acm_certificate" "todo_cert" {
  domain_name       = "${var.stack_name}-auth.auth.${aws_cognito_user_pool.todo_pool.endpoint}"
  validation_method = "DNS"
  tags = {
    Name        = "${var.stack_name}-cert"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  key_schema = [
    {
      attribute_name = "cognito-username"
      key_type       = "HASH"
    },
    {
      attribute_name = "id"
      key_type       = "RANGE"
    }
  ]
  server_side_encryption {
    enabled = true
  }
  point_in_time_recovery {
    enabled = true
  }
  tags = {
    Name        = "${var.stack_name}-table"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-api"
  description = "Todo API"
  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name                   = "${var.stack_name}-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.todo_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.todo_pool.arn]
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_get_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  api_key_required = true
}

resource "aws_api_gateway_integration" "todo_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = aws_api_gateway_method.todo_get_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.todo_api.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.todo_lambda.arn}/invocations"
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_integration.todo_get_integration]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
  tags = {
    Name        = "${var.stack_name}-deployment"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name         = "${var.stack_name}-usage-plan"
  description  = "Usage plan for Todo API"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
  }
  quota {
    limit  = 5000
    offset = 2
    period  = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Lambda Function
resource "aws_lambda_function" "todo_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.stack_name}-lambda"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "todo_lambda_role" {
  name        = "${var.stack_name}-lambda-role"
  description = "Role for Todo Lambda Function"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.stack_name}-lambda-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "todo_lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for Todo Lambda Function"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-lambda-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_lambda_attachment" {
  role       = aws_iam_role.todo_lambda_role.name
  policy_arn = aws_iam_policy.todo_lambda_policy.arn
}

# Amplify App
resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-app"
  description = "Todo App"
  platform    = "WEB"
  build_spec   = jsonencode({
    version = "1.0"
    frontend = {
      phases = {
        build = {
          commands = [
            "npm install",
            "npm run build",
          ]
        }
      }
      artifacts = {
        baseDirectory = "build"
        files         = ["**/*"]
      }
    }
  })
  tags = {
    Name        = "${var.stack_name}-app"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
  stage       = "PRODUCTION"
  auto_build  = true
}

resource "aws_amplify_environment" "todo_env" {
  app_id      = aws_amplify_app.todo_app.id
  name        = "prod"
  environment_variables = {
    API_URL = "https://${aws_api_gateway_rest_api.todo_api.id}.execute-api.${aws_api_gateway_rest_api.todo_api.region}.amazonaws.com/prod"
  }
}

# IAM Roles and Policies for API Gateway and Amplify
resource "aws_iam_role" "todo_api_gateway_role" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "Role for API Gateway"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.stack_name}-api-gateway-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "todo_api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "Policy for API Gateway"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-api-gateway-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_api_gateway_attachment" {
  role       = aws_iam_role.todo_api_gateway_role.name
  policy_arn = aws_iam_policy.todo_api_gateway_policy.arn
}

resource "aws_iam_role" "todo_amplify_role" {
  name        = "${var.stack_name}-amplify-role"
  description = "Role for Amplify"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
  tags = {
    Name        = "${var.stack_name}-amplify-role"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "todo_amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Policy for Amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:*",
        ]
        Resource = "*"
        Effect    = "Allow"
      },
    ]
  })
  tags = {
    Name        = "${var.stack_name}-amplify-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "todo_amplify_attachment" {
  role       = aws_iam_role.todo_amplify_role.name
  policy_arn = aws_iam_policy.todo_amplify_policy.arn
}

output "api_url" {
  value       = "https://${aws_api_gateway_rest_api.todo_api.id}.execute-api.${aws_api_gateway_rest_api.todo_api.region}.amazonaws.com/prod"
  description = "The URL of the API Gateway"
}

output "amplify_app_url" {
  value       = aws_amplify_app.todo_app.default_domain
  description = "The default domain of the Amplify App"
}
