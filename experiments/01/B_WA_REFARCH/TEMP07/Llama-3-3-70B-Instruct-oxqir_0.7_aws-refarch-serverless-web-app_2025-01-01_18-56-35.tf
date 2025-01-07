provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "application_name" {
  type        = string
  default     = "todo-app"
}

variable "environment" {
  type        = string
  default     = "prod"
}

variable "stack_name" {
  type        = string
  default     = "todo-app-stack"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

variable "github_repo" {
  type        = string
}

variable "github_branch" {
  type        = string
  default     = "master"
}

resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.application_name}-user-pool"
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  alias_attributes = ["email"]
  auto_verified_attributes = ["email"]
  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.application_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls                       = ["https://example.com/callback"]
  logout_urls                         = ["https://example.com/logout"]
  supported_identity_providers       = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.application_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.stack_name
  }
  server_side_encryption {
    enabled = true
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api"
  description = "API for ${var.application_name}"
  tags = {
    Name        = "${var.application_name}-api"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name        = "${var.application_name}-authorizer"
  rest_api_id = aws_api_gateway_rest_api.api.id
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  type        = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "add_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method  = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method  = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_integration" "add_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.add_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item_function.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item_function.arn}/invocations"
}

resource "aws_lambda_function" "add_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-add-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.application_name}-add-item-function"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-get-item-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 1024
  timeout       = 60
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.application_name}-get-item-function"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_role" {
  name        = "${var.application_name}-lambda-role"
  description = "Role for ${var.application_name} lambda functions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  tags = {
    Name        = "${var.application_name}-lambda-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.application_name}-lambda-policy"
  description = "Policy for ${var.application_name} lambda functions"
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
        Resource = aws_dynamodb_table.todo_table.arn
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
  tags = {
    Name        = "${var.application_name}-lambda-policy"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_amplify_app" "app" {
  name        = var.application_name
  description = "Amplify app for ${var.application_name}"
  platform    = "WEB"
  build_spec  = jsonencode({
    version = "1.0"
    frontend = {
      phases = {
        install = {
          commands = ["npm install"]
        }
        build = {
          commands = ["npm run build"]
        }
      }
      artifacts = {
        baseDirectory = "build"
        files         = ["**/*"]
      }
    }
  })
  custom_rules = [
    {
      source = "/<*>"
      target = "/index.html"
      status = "200"
    }
  ]
  tags = {
    Name        = var.application_name
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = var.github_branch
  description = "Branch for ${var.application_name}"
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.application_name}-amplify-role"
  description = "Role for ${var.application_name} amplify"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })
  tags = {
    Name        = "${var.application_name}-amplify-role"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.application_name}-amplify-policy"
  description = "Policy for ${var.application_name} amplify"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:CreateBranch",
          "amplify:DeleteBranch",
        ]
        Effect = "Allow"
        Resource = aws_amplify_app.app.arn
      },
    ]
  })
  tags = {
    Name        = "${var.application_name}-amplify-policy"
    Environment = var.environment
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.add_item_integration, aws_api_gateway_integration.get_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "test"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "usage-plan"
  description = "Usage plan for ${var.application_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.prod.stage_name
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

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_stage.prod.stage_name
}

output "lambda_function_name_add_item" {
  value = aws_lambda_function.add_item_function.function_name
}

output "lambda_function_name_get_item" {
  value = aws_lambda_function.get_item_function.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.branch.branch_name
}
