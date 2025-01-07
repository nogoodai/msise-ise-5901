provider "aws" {
  region = "us-west-2"
  version = "5.1.0"
}

variable "stack_name" {
  type        = string
  default     = "todo-stack"
}

variable "github_repository" {
  type        = string
  default     = "https://github.com/your-username/your-repo-name"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

variable "github_token" {
  type        = string
  sensitive   = true
}

resource "aws_cognito_user_pool" "todo_pool" {
  name                = "${var.stack_name}-user-pool"
  alias_attributes   = ["email"]
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
    require_numbers   = false
    require_symbols   = false
  }
}

resource "aws_cognito_user_pool_client" "todo_client" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.todo_pool.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "todo_domain" {
  domain               = "${var.stack_name}-auth"
  user_pool_id         = aws_cognito_user_pool.todo_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
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
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.stack_name}-api"
  description = "Todo API"
}

resource "aws_api_gateway_resource" "todo_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "todo_get" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_post" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_put" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_method" "todo_delete" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.todo_resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.todo_authorizer.id
}

resource "aws_api_gateway_authorizer" "todo_authorizer" {
  name           = "${var.stack_name}-authorizer"
  type           = "COGNITO_USER_POOLS"
  provider_arns  = [aws_cognito_user_pool.todo_pool.arn]
  rest_api_id    = aws_api_gateway_rest_api.todo_api.id
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on = [aws_api_gateway_method.todo_get, aws_api_gateway_method.todo_post, aws_api_gateway_method.todo_put, aws_api_gateway_method.todo_delete]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "todo_usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Todo usage plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.todo_api.id
    stage  = aws_api_gateway_deployment.todo_deployment.stage_name
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

resource "aws_lambda_function" "todo_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-lambda"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.todo_lambda_role.arn
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }
}

resource "aws_iam_role" "todo_lambda_role" {
  name        = "${var.stack_name}-lambda-role"
  description = "Todo lambda role"
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

resource "aws_iam_policy" "todo_lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Todo lambda policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_lambda_policy_attachment" {
  role       = aws_iam_role.todo_lambda_role.name
  policy_arn = aws_iam_policy.todo_lambda_policy.arn
}

resource "aws_amplify_app" "todo_app" {
  name        = "${var.stack_name}-app"
  description = "Todo app"
  platform    = "WEB"
  build_spec  = file("./buildspec.yml")
  environment {
    name  = "master"
    value = var.github_branch
  }
  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "200"
  }
}

resource "aws_amplify_branch" "todo_branch" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_iam_role" "todo_api_gateway_role" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "Todo API Gateway role"
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

resource "aws_iam_policy" "todo_api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "Todo API Gateway policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_api_gateway_policy_attachment" {
  role       = aws_iam_role.todo_api_gateway_role.name
  policy_arn = aws_iam_policy.todo_api_gateway_policy.arn
}

resource "aws_iam_role" "todo_amplify_role" {
  name        = "${var.stack_name}-amplify-role"
  description = "Todo Amplify role"
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

resource "aws_iam_policy" "todo_amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Todo Amplify policy"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
          "amplify:CreateDomainAssociation",
          "amplify:CreateWebhook"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "todo_amplify_policy_attachment" {
  role       = aws_iam_role.todo_amplify_role.name
  policy_arn = aws_iam_policy.todo_amplify_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "lambda_function_name" {
  value = aws_lambda_function.todo_lambda.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.todo_branch.branch_name
}
