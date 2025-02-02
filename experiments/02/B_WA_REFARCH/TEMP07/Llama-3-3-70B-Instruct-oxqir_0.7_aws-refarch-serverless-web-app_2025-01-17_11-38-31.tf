provider "aws" {
  region = "us-west-2"
  version = "= 5.1.0"
}

variable "application_name" {
  default = "todo-app"
}

variable "environment" {
  default = "prod"
}

variable "stack_name" {
  default = "todo-stack"
}

variable "github_repository" {
  default = "https://github.com/your-repo/todo-app"
}

variable "github_branch" {
  default = "master"
}

resource "aws_cognito_user_pool" "todo_app_pool" {
  name                = "${var.application_name}-${var.environment}-pool"
  alias_attributes   = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_uppercase = true
    require_lowercase = true
  }
}

resource "aws_cognito_user_pool_client" "todo_app_client" {
  name                = "${var.application_name}-${var.environment}-client"
  user_pool_id       = aws_cognito_user_pool.todo_app_pool.id
  generate_secret    = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
}

resource "aws_cognito_user_pool_domain" "todo_app_domain" {
  domain               = "${var.application_name}-${var.environment}"
  user_pool_id         = aws_cognito_user_pool.todo_app_pool.id
}

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
}

resource "aws_api_gateway_rest_api" "todo_api" {
  name        = "${var.application_name}-${var.environment}-api"
  description = "Todo API"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.application_name}-${var.environment}-authorizer"
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.todo_app_pool.arn]
  rest_api_id   = aws_api_gateway_rest_api.todo_api.id
}

resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method  = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "get_item_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method  = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "put_item_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method  = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_method" "delete_item_method" {
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method  = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_deployment" "todo_deployment" {
  depends_on  = [aws_api_gateway_method.post_item_method, aws_api_gateway_method.get_item_method, aws_api_gateway_method.put_item_method, aws_api_gateway_method.delete_item_method]
  rest_api_id = aws_api_gateway_rest_api.todo_api.id
  stage_name  = "prod"
}

resource "aws_lambda_function" "add_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "get_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "put_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-put-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_lambda_function" "delete_item_function" {
  filename      = "lambda_function_payload.zip"
  function_name = "${var.application_name}-${var.environment}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_exec_role.arn
  memory_size   = 1024
  timeout       = 60
}

resource "aws_iam_role" "lambda_exec_role" {
  name        = "${var.application_name}-${var.environment}-lambda-exec"
  description = "Lambda execution role"

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
  name        = "${var.application_name}-${var.environment}-lambda-policy"
  description = "Lambda policy"

  policy = jsonencode({
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
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role" "apigateway_exec_role" {
  name        = "${var.application_name}-${var.environment}-apigateway-exec"
  description = "API Gateway execution role"

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

resource "aws_iam_policy" "apigateway_policy" {
  name        = "${var.application_name}-${var.environment}-apigateway-policy"
  description = "API Gateway policy"

  policy = jsonencode({
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
}

resource "aws_iam_role_policy_attachment" "apigateway_attach" {
  role       = aws_iam_role.apigateway_exec_role.name
  policy_arn = aws_iam_policy.apigateway_policy.arn
}

resource "aws_amplify_app" "todo_app" {
  name        = "${var.application_name}-${var.environment}"
  description = "Todo app"
  platform    = "WEB"

  build_spec = jsonencode({
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

  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "200"
  }

  environment_variables = {
    BUCKET_NAME = aws_s3_bucket.todo_bucket.id
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.todo_app.id
  branch_name = var.github_branch
}

resource "aws_s3_bucket" "todo_bucket" {
  bucket        = "${var.application_name}-${var.environment}-bucket"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "todo_policy" {
  bucket = aws_s3_bucket.todo_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource = "${aws_s3_bucket.todo_bucket.arn}/*"
      },
    ]
  })
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.todo_app_pool.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.todo_app_client.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.todo_api.id
}

output "lambda_function_name" {
  value = aws_lambda_function.add_item_function.function_name
}

output "apigateway_exec_role_arn" {
  value = aws_iam_role.apigateway_exec_role.arn
}

output "amplify_app_id" {
  value = aws_amplify_app.todo_app.id
}

output "amplify_branch_name" {
  value = aws_amplify_branch.master.branch_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.todo_bucket.id
}
