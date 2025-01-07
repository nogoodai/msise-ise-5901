provider "aws" {
  region = "us-west-2"
  required_providers {
    aws = "= 5.1.0"
  }
}

variable "stack_name" {
  type = string
  default = "my-stack"
}

variable "application_name" {
  type = string
  default = "my-application"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "this" {
  name                = "${var.application_name}-user-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]
  email_verification_subject = "Your verification code"
}

resource "aws_cognito_user_pool_client" "this" {
  name                = "${var.application_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.this.id
  generate_secret    = false
  supported_identity_providers = ["COGNITO"]
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.application_name}.${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user_pool_policy" "this" {
  name   = "${var.application_name}-user-pool-policy"
  user_pool_id = aws_cognito_user_pool.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PasswordPolicy"
        Effect    = "Allow"
        Action    = "cognito-idp:CreateUserPool"
        Resource = "*"
        Condition = {
          "StringLength" = {
            "cognito-idp:PasswordLength" = "6"
          }
        }
      },
      {
        Sid       = "PasswordPolicy"
        Effect    = "Allow"
        Action    = "cognito-idp:CreateUserPool"
        Resource = "*"
        Condition = {
          "StringEquals" = {
            "cognito-idp:PasswordRequiresUppercase" = "true"
          }
        }
      },
      {
        Sid       = "PasswordPolicy"
        Effect    = "Allow"
        Action    = "cognito-idp:CreateUserPool"
        Resource = "*"
        Condition = {
          "StringEquals" = {
            "cognito-idp:PasswordRequiresLowercase" = "true"
          }
        }
      },
    ]
  })
}

# DynamoDB Table
resource "aws_dynamodb_table" "this" {
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
}

# API Gateway
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.application_name}-api"
  description = "API for ${var.application_name}"
}

resource "aws_api_gateway_authorizer" "this" {
  name        = "${var.application_name}-authorizer"
  rest_api_id = aws_api_gateway_rest_api.this.id
  type        = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.this.arn]
}

resource "aws_api_gateway_resource" "this" {
  path_part   = "item"
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.this.id
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.this.id
}

resource "aws_api_gateway_integration" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.this.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_api_gateway_rest_api.this.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.add_item.arn}/invocations"
}

resource "aws_api_gateway_deployment" "this" {
  depends_on  = [aws_api_gateway_integration.post_item]
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = "prod"
}

resource "aws_api_gateway_usage_plan" "this" {
  name        = "${var.application_name}-usage-plan"
  description = "Usage plan for ${var.application_name}"
}

resource "aws_api_gateway_usage_plan_key" "this" {
  usage_plan_id = aws_api_gateway_usage_plan.this.id
  key_type      = "API_KEY"
}

# Lambda Functions
resource "aws_lambda_function" "add_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = []
    subnet_ids          = []
  }
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "get_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = []
    subnet_ids          = []
  }
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "get_all_items" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-get-all-items"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = []
    subnet_ids          = []
  }
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "update_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-update-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = []
    subnet_ids          = []
  }
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "complete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-complete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = []
    subnet_ids          = []
  }
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec.arn
  vpc_config {
    security_group_ids = []
    subnet_ids          = []
  }
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

# Amplify App
resource "aws_amplify_app" "this" {
  name        = "${var.application_name}-amplify-app"
  description = "Amplify app for ${var.application_name}"
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = "master"
}

# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_exec" {
  name        = "${var.application_name}-api-gateway-exec"
  description = "Execution role for API Gateway"

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
}

resource "aws_iam_policy" "api_gateway_exec" {
  name        = "${var.application_name}-api-gateway-exec-policy"
  description = "Policy for API Gateway execution role"

  policy      = jsonencode({
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

resource "aws_iam_role_policy_attachment" "api_gateway_exec" {
  role       = aws_iam_role.api_gateway_exec.name
  policy_arn = aws_iam_policy.api_gateway_exec.arn
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.application_name}-lambda-exec"
  description = "Execution role for Lambda"

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
}

resource "aws_iam_policy" "lambda_exec" {
  name        = "${var.application_name}-lambda-exec-policy"
  description = "Policy for Lambda execution role"

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
        Resource = aws_dynamodb_table.this.arn
        Effect    = "Allow"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
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

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

resource "aws_iam_role" "amplify_exec" {
  name        = "${var.application_name}-amplify-exec"
  description = "Execution role for Amplify"

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
}

resource "aws_iam_policy" "amplify_exec" {
  name        = "${var.application_name}-amplify-exec-policy"
  description = "Policy for Amplify execution role"

  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "amplify:GetApp",
          "amplify:GetBranch",
          "amplify:CreateBranch",
          "amplify:UpdateBranch",
          "amplify:DeleteBranch"
        ]
        Resource = "*"
        Effect    = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_exec" {
  role       = aws_iam_role.amplify_exec.name
  policy_arn = aws_iam_policy.amplify_exec.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.this.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.this.name
}

output "api_gateway_rest_api_id" {
  value = aws_api_gateway_rest_api.this.id
}

output "api_gateway_deployment_id" {
  value = aws_api_gateway_deployment.this.id
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.add_item.function_name,
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.get_all_items.function_name,
    aws_lambda_function.update_item.function_name,
    aws_lambda_function.complete_item.function_name,
    aws_lambda_function.delete_item.function_name
  ]
}

output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.this.branch_name
}
