provider "aws" {
  region = "us-west-2"
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
}

variable "github_branch" {
  type        = string
  default     = "master"
}

variable "github_repository" {
  type        = string
  default     = "https://github.com/user/todo-app"
}

variable "github_oauth_token" {
  type        = string
  sensitive   = true
}

# Create Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  alias_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols = false
    require_numbers = false
  }
}

# Create Cognito User Pool Client
resource "aws_cognito_user_pool_client" "client" {
  name = "${var.stack_name}-client"

  user_pool_id = aws_cognito_user_pool.user_pool.id

  supported_identity_providers = ["COGNITO"]
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  generate_secret                      = false
}

# Create Custom Domain for Cognito
resource "aws_cognito_user_pool_domain" "domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

# Create DynamoDB Table
resource "aws_dynamodb_table" "table" {
  name           = "${var.stack_name}-todo-table"
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

  global_secondary_index {
    name               = "id-index"
    hash_key           = "id"
    read_capacity_units = 5
    write_capacity_units = 5
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

  table_status = "ACTIVE"

  server_side_encryption {
    enabled = true
  }
}

# Create API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "REST API for Todo App"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name        = "${var.stack_name}-authorizer"
  rest_api_id = aws_api_gateway_rest_api.api.id
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "put_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_method" "delete_item_method" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.stack_name}-usage-plan"
  description = "Usage plan for Todo App API"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
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

# Create Lambda Function
resource "aws_lambda_function" "lambda_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.stack_name}-lambda-function"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.table.name
    }
  }
}

# Create Lambda Function Policies
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.stack_name}-lambda-policy"
  description = "Policy for Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Create IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name        = "${var.stack_name}-lambda-role"
  description = "Role for Lambda function"

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

# Create Amplify App
resource "aws_amplify_app" "app" {
  name        = "${var.stack_name}-app"
  description = "Amplify app for Todo App"

  build_spec = file("./buildspec.yml")

  environment {
    name  = "AWS_ACCESS_KEY_ID"
    value = aws_iam_access_key.key.id
  }

  environment {
    name  = "AWS_SECRET_ACCESS_KEY"
    value = aws_iam_access_key.key.secret
  }

  environment {
    name  = "AWS_REGION"
    value = aws_provider.region
  }

  environment {
    name  = "GITHUB_OAUTH_TOKEN"
    value = var.github_oauth_token
  }
}

resource "aws_amplify_branch" "branch" {
  app_id      = aws_amplify_app.app.id
  branch_name = var.github_branch
}

# Create IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name        = "${var.stack_name}-amplify-role"
  description = "Role for Amplify app"

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

# Create IAM Policy for Amplify
resource "aws_iam_policy" "amplify_policy" {
  name        = "${var.stack_name}-amplify-policy"
  description = "Policy for Amplify app"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

# Create API Gateway Role
resource "aws_iam_role" "api_gateway_role" {
  name        = "${var.stack_name}-api-gateway-role"
  description = "Role for API Gateway"

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

# Create IAM Policy for API Gateway
resource "aws_iam_policy" "api_gateway_policy" {
  name        = "${var.stack_name}-api-gateway-policy"
  description = "Policy for API Gateway"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.table.name
}

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.api.id
}

output "lambda_function_name" {
  value = aws_lambda_function.lambda_function.function_name
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.branch.branch_name
}
