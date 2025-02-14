terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources."
  type        = string
  default     = "us-east-1"
}

variable "stack_name" {
  description = "The name of the stack."
  type        = string
  default     = "myapp"
}

variable "github_repository" {
  description = "GitHub repository for Amplify app."
  type        = string
}

variable "github_token" {
  description = "GitHub OAuth token for Amplify."
  type        = string
  sensitive   = true
}

resource "aws_cognito_user_pool" "user_pool" {
  name                       = "${var.stack_name}-user-pool"
  auto_verified_attributes   = ["email"]
  mfa_configuration          = "ON"

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
    Project     = "myapp"
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  name               = "${var.stack_name}-client"
  generate_secret    = true

  oauth {
    flows  = ["authorization_code", "implicit"]
    scopes = ["email", "phone", "openid"]
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key    = "cognito-username"
  range_key   = "id"

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

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "production"
    Project     = "myapp"
  }
}

resource "aws_apigatewayv2_api" "api" {
  name          = "${var.stack_name}-api"
  protocol_type = "HTTP"

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = "myapp"
  }
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id          = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name            = "${var.stack_name}-authorizer"
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = aws_cognito_user_pool.user_pool.endpoint
  }
}

resource "aws_apigatewayv2_stage" "api_stage" {
  api_id     = aws_apigatewayv2_api.api.id
  name       = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_log_group.arn
    format          = jsonencode({
      requestId      = "$context.requestId",
      ip             = "$context.identity.sourceIp",
      caller         = "$context.identity.caller",
      user           = "$context.identity.user",
      requestTime    = "$context.requestTime",
      httpMethod     = "$context.httpMethod",
      resourcePath   = "$context.resourcePath",
      status         = "$context.status",
      protocol       = "$context.protocol",
      responseLength = "$context.responseLength"
    })
  }

  tags = {
    Name        = "${var.stack_name}-api-stage"
    Environment = "production"
    Project     = "myapp"
  }
}

resource "aws_cloudwatch_log_group" "api_gw_log_group" {
  name = "/aws/apigateway/${var.stack_name}-api-logs"
  retention_in_days = 90
}

resource "aws_apigatewayv2_api_mapping" "api_mapping" {
  api_id      = aws_apigatewayv2_api.api.id
  domain_name = aws_cognito_user_pool_domain.user_pool_domain.domain
  stage       = aws_apigatewayv2_stage.api_stage.name
}

resource "aws_apigatewayv2_route" "routes" {
  for_each = {
    "POST /item"        = "AddItemFunction"
    "GET /item/{id}"    = "GetItemFunction"
    "GET /item"         = "GetAllItemsFunction"
    "PUT /item/{id}"    = "UpdateItemFunction"
    "POST /item/{id}/done" = "CompleteItemFunction"
    "DELETE /item/{id}" = "DeleteItemFunction"
  }

  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.key
  target    = "integrations/${aws_lambda_function.lambda_functions[each.value].id}"
}

resource "aws_lambda_permission" "api_gateway" {
  for_each = aws_apigatewayv2_route.routes

  statement_id  = each.key
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_functions[each.value].arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/${each.key}"
}

resource "aws_lambda_function" "lambda_functions" {
  for_each = {
    AddItemFunction        = "POST /item"
    GetItemFunction        = "GET /item/{id}"
    GetAllItemsFunction    = "GET /item"
    UpdateItemFunction     = "PUT /item/{id}"
    CompleteItemFunction   = "POST /item/{id}/done"
    DeleteItemFunction     = "DELETE /item/{id}"
  }

  function_name = "${var.stack_name}-${each.key}"
  runtime       = "nodejs16.x"
  handler       = "index.handler"
  memory_size   = 1024
  timeout       = 60
  tracing_config {
    mode = "Active"
  }
  source_code_hash = filebase64sha256("lambda/${each.key}.zip")
  filename         = "lambda/${each.key}.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.todo_table.name
    }
  }

  role = aws_iam_role.lambda_exec_role.arn

  tags = {
    Name        = "${var.stack_name}-${each.key}"
    Environment = "production"
    Project     = "myapp"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-exec-role"

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
    Name        = "${var.stack_name}-lambda-exec-role"
    Environment = "production"
    Project     = "myapp"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_amplify_app" "amplify_app" {
  name = "${var.stack_name}-amplify-app"

  repository = var.github_repository
  oauth_token = var.github_token

  build_spec = file("amplify-buildspec.yml")

  environment_variables = {
    "_LIVE_UPDATES" = "[{\"pkg\":\"package.json\",\"type\":\"npm\"}]"
  }

  tags = {
    Name        = "${var.stack_name}-amplify-app"
    Environment = "production"
    Project     = "myapp"
  }
}

resource "aws_amplify_branch" "amplify_branch" {
  app_id = aws_amplify_app.amplify_app.id
  branch_name = "master"

  enable_auto_build = true
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.stack_name}-api-gateway-role"

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

  tags = {
    Name        = "${var.stack_name}-api-gateway-role"
    Environment = "production"
    Project     = "myapp"
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

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
    Name        = "${var.stack_name}-amplify-role"
    Environment = "production"
    Project     = "myapp"
  }
}

resource "aws_accessanalyzer_analyzer" "example" {
  analyzer_name = "${var.stack_name}-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name        = "${var.stack_name}-analyzer"
    Environment = "production"
    Project     = "myapp"
  }
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool."
  value       = aws_cognito_user_pool.user_pool.id
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client."
  value       = aws_cognito_user_pool_client.user_pool_client.id
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  description = "The URL of the API Gateway."
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "amplify_app_id" {
  description = "ID of the Amplify App."
  value       = aws_amplify_app.amplify_app.id
}
