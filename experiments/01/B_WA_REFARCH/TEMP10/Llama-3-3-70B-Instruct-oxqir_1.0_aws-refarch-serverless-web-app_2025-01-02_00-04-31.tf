# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Set up project variables
variable "project_name" {
  type    = string
  default = "serverless-web-app"
}

variable "stack_name" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

# Configure AWS provider
provider "aws" {
  region = var.region
}

# Cognito User Pool for authentication and user management
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.stack_name}-user-pool"

  username_configuration {
    case_sensitive = false
  }

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }

  email_configuration {
    email_verification_message = "Your verification code is {####}."
    email_verification_subject = "Your verification code"
  }

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Cognito User Pool Client for OAuth2 flows and authentication scopes
resource "aws_cognito_user_pool_client" "main" {
  name                = "${var.project_name}-${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.main.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = [
    "email",
    "phone",
    "openid"
  ]
  allowed_oauth_flows_user_pool_client = true
  callback_urls = [
    "https://${var.project_name}-${var.stack_name}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"
  ]

  tags = {
    Name        = "${var.project_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# Custom domain for Cognito User Pool
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB table for data storage with partition and sort keys
resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
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
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# API Gateway for serving API requests and integrating with Cognito for authorization
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-${var.stack_name}-api"
  description = "API for ${var.project_name}"
}

resource "aws_api_gateway_authorizer" "main" {
  name           = "${var.project_name}-${var.stack_name}-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = ["arn:aws:cognito-idp:${var.region}:${aws_cognito_user_pool.main.id}:userpool/${aws_cognito_user_pool.main.id}"]
}

resource "aws_api_gateway_resource" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_method" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.main.id
}

resource "aws_api_gateway_deployment" "main" {
  depends_on  = [aws_api_gateway_method.get_item, aws_api_gateway_method.post_item, aws_api_gateway_method.get_all_items, aws_api_gateway_method.put_item, aws_api_gateway_method.delete_item]
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = var.stack_name
}

# Lambda function for CRUD operations on DynamoDB
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_functions/add_item.zip"
  function_name = "${var.project_name}-${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-add-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_functions/get_item.zip"
  function_name = "${var.project_name}-${var.stack_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-get-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_functions/get_all_items.zip"
  function_name = "${var.project_name}-${var.stack_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-get-all-items"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_functions/update_item.zip"
  function_name = "${var.project_name}-${var.stack_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-update-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_functions/complete_item.zip"
  function_name = "${var.project_name}-${var.stack_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-complete-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_functions/delete_item.zip"
  function_name = "${var.project_name}-${var.stack_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }
  tags = {
    Name        = "${var.project_name}-${var.stack_name}-delete-item"
    Environment = var.stack_name
    Project     = var.project_name
  }
}

# API Gateway integrations
resource "aws_api_gateway_integration" "add_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = aws_api_gateway_method.get_all_items.http_method
  integration_http_method = "GET"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${aws_lambda_function.get_all_items.arn}/invocations"
}

resource "aws_api_gateway_integration" "update_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "PUT"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${aws_lambda_function.update_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.main.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "DELETE"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.region}:${aws_lambda_function.delete_item.arn}/invocations"
}

# Amplify app for frontend hosting and deployment from GitHub
resource "aws_amplify_app" "main" {
  name        = "${var.project_name}-${var.stack_name}"
  description = "Amplify app for ${var.project_name}"
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
}

# IAM roles and policies for API Gateway, Amplify, and Lambda
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.project_name}-${var.stack_name}-api-gateway-exec"
  description = "Execution role for API Gateway"

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

resource "aws_iam_policy" "api_gateway_exec" {
  name        = "${var.project_name}-${var.stack_name}-api-gateway-exec-policy"
  description = "Policy for API Gateway execution"

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
        Resource = "arn:aws:logs:${var.region}:${aws_api_gateway_rest_api.main.id}:log-group:/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.project_name}-${var.stack_name}-amplify-exec"
  description = "Execution role for Amplify"

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

resource "aws_iam_policy" "amplify_exec" {
  name        = "${var.project_name}-${var.stack_name}-amplify-exec-policy"
  description = "Policy for Amplify execution"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:CreateApp",
          "amplify:CreateBranch",
          "amplify:CreateDeployment",
          "amplify:DeleteApp",
          "amplify:DeleteBranch",
          "amplify:DeleteDeployment",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.project_name}-${var.stack_name}-lambda-exec"
  description = "Execution role for Lambda"

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

resource "aws_iam_policy" "lambda_exec" {
  name        = "${var.project_name}-${var.stack_name}-lambda-exec-policy"
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
        Resource = "arn:aws:logs:${var.region}:${aws_lambda_function.add_item.arn}:log-group:/aws/lambda/${aws_lambda_function.add_item.function_name}"
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
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

# Output critical information
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "api_gateway_stage_name" {
  value = aws_api_gateway_deployment.main.stage_name
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.main.branch_name
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.update_item.function_name,
    aws_lambda_function.complete_item.function_name,
    aws_lambda_function.delete_item.function_name,
  ]
}
