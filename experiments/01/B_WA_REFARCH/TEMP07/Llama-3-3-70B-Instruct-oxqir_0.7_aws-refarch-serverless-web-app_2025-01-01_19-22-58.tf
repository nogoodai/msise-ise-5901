provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "my-stack"
  description = "The name of the stack"
}

variable "github_repo" {
  type        = string
  default     = "https://github.com/my-repo/my-repo.git"
  description = "The URL of the GitHub repository"
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The name of the GitHub branch"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

# Cognito Domain
resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.this.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
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
    Project     = var.stack_name
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.stack_name}-api"
  description = "The API for ${var.stack_name}"
}

resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_authorizer" "this" {
  name           = "${var.stack_name}-authorizer"
  type           = "COGNITO_USER_POOLS"
  provider_arns  = [aws_cognito_user_pool.this.arn]
  rest_api_id    = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_method.get_item,
    aws_api_gateway_method.post_item,
    aws_api_gateway_method.put_item,
    aws_api_gateway_method.delete_item
  ]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.stack_name}-usage-plan"
  description = "The usage plan for ${var.stack_name}"
  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_deployment.this.stage_name
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

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.this.name
    }
  }
}

# API Gateway Integrations
resource "aws_api_gateway_integration" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${data.aws_caller_identity.current.account_id}:function:${aws_lambda_function.add_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${data.aws_caller_identity.current.account_id}:function:${aws_lambda_function.get_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${data.aws_caller_identity.current.account_id}:function:${aws_lambda_function.get_all_items.function_name}/invocations"
}

resource "aws_api_gateway_integration" "update_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${data.aws_caller_identity.current.account_id}:function:${aws_lambda_function.update_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "complete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${data.aws_caller_identity.current.account_id}:function:${aws_lambda_function.complete_item.function_name}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${aws_api_gateway_rest_api.this.region}:${data.aws_caller_identity.current.account_id}:function:${aws_lambda_function.delete_item.function_name}/invocations"
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.stack_name}-app"
  description = "The Amplify app for ${var.stack_name}"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.github_branch
}

resource "aws_amplify_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment = "prod"
  name        = "prod-env"
}

resource "aws_amplify_backend_environment" "this" {
  app_id      = aws_amplify_app.this.id
  environment_name = aws_amplify_environment.this.name
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.stack_name}-api-gateway-exec"
  description = "The execution role for the API Gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "api_gateway_exec" {
  name   = "${var.stack_name}-api-gateway-exec-policy"
  role   = aws_iam_role.api_gateway_exec.id
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
      }
    ]
  })
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.stack_name}-lambda-exec"
  description = "The execution role for the Lambda functions"

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
}

resource "aws_iam_role_policy" "lambda_exec" {
  name   = "${var.stack_name}-lambda-exec-policy"
  role   = aws_iam_role.lambda_exec.id
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
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.stack_name}-amplify-exec"
  description = "The execution role for the Amplify app"

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
}

resource "aws_iam_role_policy" "amplify_exec" {
  name   = "${var.stack_name}-amplify-exec-policy"
  role   = aws_iam_role.amplify_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateEnvironment",
          "amplify:CreateBackendEnvironment",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${aws_api_gateway_rest_api.this.region}.amazonaws.com/prod"
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}
