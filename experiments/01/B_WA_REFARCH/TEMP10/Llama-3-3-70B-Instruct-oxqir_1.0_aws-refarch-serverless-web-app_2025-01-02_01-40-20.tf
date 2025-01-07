provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-west-2"
}

variable "stack_name" {
  default = "serverless-web-application"
}

variable "project_name" {
  default = "todo-list"
}

resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  username_attributes = ["email"]
  email_verification_message = "Your verification code is {####}. "
  email_verification_subject  = "Your verification code"
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "${var.project_name}-cognito-user-pool"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers = ["COGNITO"]
  callback_urls = ["https://${var.stack_name}.auth.us-west-2.amazoncognito.com/oauth2/idpresponse"]
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
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
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "${var.project_name}-todo-table"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "api_gateway" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for todo list application"
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  parent_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "get_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "put_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_method" "delete_method" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name                             = "${var.stack_name}-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.api_gateway.id
  type                             = "COGNITO_USER_POOLS"
  provider_arns                   = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_method.post_method, aws_api_gateway_method.get_method, aws_api_gateway_method.put_method, aws_api_gateway_method.delete_method]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name         = "${var.stack_name}-usage-plan"
  description  = "Usage plan for todo list application"
  api_stages {
    api_id = aws_api_gateway_rest_api.api_gateway.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }
  quota {
    limit  = 5000
    offset = 0
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_lambda_function" "add_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      DYNAMODB_TABLE = "todo-table-${var.stack_name}"
    }
  }
  tags = {
    Name        = "${var.project_name}-add-item-lambda"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      DYNAMODB_TABLE = "todo-table-${var.stack_name}"
    }
  }
  tags = {
    Name        = "${var.project_name}-get-item-lambda"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_all_items_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      DYNAMODB_TABLE = "todo-table-${var.stack_name}"
    }
  }
  tags = {
    Name        = "${var.project_name}-get-all-items-lambda"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "update_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      DYNAMODB_TABLE = "todo-table-${var.stack_name}"
    }
  }
  tags = {
    Name        = "${var.project_name}-update-item-lambda"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "complete_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      DYNAMODB_TABLE = "todo-table-${var.stack_name}"
    }
  }
  tags = {
    Name        = "${var.project_name}-complete-item-lambda"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "delete_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn
  environment {
    variables = {
      DYNAMODB_TABLE = "todo-table-${var.stack_name}"
    }
  }
  tags = {
    Name        = "${var.project_name}-delete-item-lambda"
    Environment = "prod"
    Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "Role for API Gateway to write logs to CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })
}

resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "Policy for API Gateway to write logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

resource "aws_iam_role" "lambda_role" {
  name        = "${var.stack_name}-lambda-role"
  description = "Role for Lambda functions to interact with DynamoDB and publish metrics to CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid      = ""
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for Lambda functions to interact with DynamoDB and publish metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = aws_dynamodb_table.todo_table.arn
        Effect    = "Allow"
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_amplify_app" "app" {
  name        = "${var.stack_name}-app"
  description = "Amplify app for todo list application"
  platform    = "WEB"
  build_spec  = file("./buildspec.yml")
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = "master"
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api_gateway.id
}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_deployment.deployment.rest_api_id}.execute-api.${var.aws_region}.amazonaws.com/prod/"
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.add_item_function.function_name,
    aws_lambda_function.get_item_function.function_name,
    aws_lambda_function.get_all_items_function.function_name,
    aws_lambda_function.update_item_function.function_name,
    aws_lambda_function.complete_item_function.function_name,
    aws_lambda_function.delete_item_function.function_name
  ]
}
