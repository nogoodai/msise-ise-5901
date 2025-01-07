provider "aws" {
  region = "us-west-2"
  version = "4.63.0"
}

variable "stack_name" {
  type        = string
  default     = "my-serverless-stack"
}

variable "application_name" {
  type        = string
  default     = "my-web-application"
}

variable "github_repository" {
  type        = string
  default     = "https://github.com/my-username/my-repo"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

resource "aws_cognito_user_pool" "my_user_pool" {
  name                = "${var.stack_name}-user-pool"
  email_configuration {
    source_arn = aws_ses_identity.my_identity.arn
    email_sending_account = "DEVELOPER"
  }
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
  alias_attributes = ["email"]
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "my_user_pool_client" {
  name = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.my_user_pool.id

  supported_identity_providers = ["COGNITO"]

  callback_urls = [
    "https://${var.application_name}.com/callback"
  ]

  logout_urls = [
    "https://${var.application_name}.com/logout"
  ]

  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "my_user_pool_domain" {
  domain       = "${var.application_name}-auth"
  user_pool_id = aws_cognito_user_pool.my_user_pool.id
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
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_rest_api" "my_api" {
  name        = "${var.stack_name}-api"
  description = "My API Gateway"
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_api_gateway_authorizer" "my_authorizer" {
  name        = "${var.stack_name}-authorizer"
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  provider_arns = [aws_cognito_user_pool.my_user_pool.arn]
  type        = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.my_authorizer.id
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.get_item_method.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item_lambda.arn}/invocations"
}

resource "aws_api_gateway_deployment" "my_deployment" {
  depends_on  = [aws_api_gateway_integration.get_item_integration]
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "my_usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "My usage plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.my_api.id
    stage  = aws_api_gateway_deployment.my_deployment.stage_name
  }

  quota {
    limit          = 5000
    offset         = 0
    period         = "DAY"
  }

  throttle {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "get_item_lambda" {
  filename      = "get-item-lambda.zip"
  function_name = "${var.stack_name}-get-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  publish       = true
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-get-item-lambda"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "add_item_lambda" {
  filename      = "add-item-lambda.zip"
  function_name = "${var.stack_name}-add-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  publish       = true
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-add-item-lambda"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "update_item_lambda" {
  filename      = "update-item-lambda.zip"
  function_name = "${var.stack_name}-update-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  publish       = true
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-update-item-lambda"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_lambda_function" "delete_item_lambda" {
  filename      = "delete-item-lambda.zip"
  function_name = "${var.stack_name}-delete-item-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  publish       = true
  timeout       = 60
  memory_size   = 1024
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-delete-item-lambda"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec"
  description = " Execution role for Lambda functions"

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

  tags = {
    Name        = "${var.stack_name}-lambda-exec"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for Lambda execution"

  policy = jsonencode({
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
        Action = "cloudwatch:PutMetricData"
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-policy"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_amplify_app" "my_app" {
  name        = var.application_name
  description = "My Amplify app"

  tags = {
    Name        = var.application_name
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_amplify_branch" "my_branch" {
  app_id      = aws_amplify_app.my_app.id
  branch_name = "master"

  stage = "PRODUCTION"

  tags = {
    Name        = "master"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_amplify_environment" "my_env" {
  app_id      = aws_amplify_app.my_app.id
  branch_name = aws_amplify_branch.my_branch.branch_name
  name        = "prod"

  tags = {
    Name        = "prod"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role" "amplify_role" {
  name        = "${var.stack_name}-amplify-exec"
  description = " Execution role for Amplify"

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

  tags = {
    Name        = "${var.stack_name}-amplify-exec"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Policy for Amplify execution"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateEnvironment",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })

  tags = {
    Name        = "${var.stack_name}-amplify-policy"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

resource "aws_cloudwatch_log_group" "my_log_group" {
  name        = "${var.stack_name}-log-group"
  retention_in_days = 30
}

resource "aws_cloudwatch_metric_alarm" "my_alarm" {
  alarm_name          = "${var.stack_name}-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Error"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.my_topic.arn]
}

resource "aws_sns_topic" "my_topic" {
  name         = "${var.stack_name}-topic"
}

resource "aws_sns_topic_subscription" "my_subscription" {
  topic_arn = aws_sns_topic.my_topic.arn
  protocol  = "email"
  endpoint  = "my-email@example.com"
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.my_user_pool.id
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.my_user_pool_client.id
}

output "cognito_domain" {
  value       = aws_cognito_user_pool_domain.my_user_pool_domain.domain
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.my_api.id
}

output "api_gateway_stage_name" {
  value       = aws_api_gateway_deployment.my_deployment.stage_name
}

output "lambda_function_names" {
  value       = [
    aws_lambda_function.get_item_lambda.function_name,
    aws_lambda_function.add_item_lambda.function_name,
    aws_lambda_function.update_item_lambda.function_name,
    aws_lambda_function.delete_item_lambda.function_name,
  ]
}
