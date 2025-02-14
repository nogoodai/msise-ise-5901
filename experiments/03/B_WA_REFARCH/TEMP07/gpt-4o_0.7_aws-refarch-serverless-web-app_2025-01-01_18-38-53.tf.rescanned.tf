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
  default     = "us-east-1"
  type        = string
}

variable "stack_name" {
  description = "The name of the stack for uniqueness."
  default     = "my-app-stack"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository for Amplify source."
  type        = string
}

variable "github_token" {
  description = "GitHub token for accessing the repository securely."
  type        = string
  sensitive   = true
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "${var.stack_name}-user-pool"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  mfa_configuration = "ON"

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id = aws_cognito_user_pool.user_pool.id
  name         = "${var.stack_name}-client"

  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]
  generate_secret = true
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = "${var.stack_name}-auth"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5

  hash_key  = "cognito-username"
  range_key = "id"

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
    Name        = "${var.stack_name}-todo-table"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.stack_name}-api"
  description = "API for ${var.stack_name}"

  endpoint_configuration {
    types = ["PRIVATE"]
  }

  minimum_compression_size = 0

  body = jsonencode({
    openapi = "3.0.1",
    info    = {
      title   = "${var.stack_name} API"
      version = "1.0"
    },
    paths   = {
      "/item" = {
        post = {
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.add_item.invoke_arn
            httpMethod = "POST"
            type = "AWS_PROXY"
          }
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        },
        get = {
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.get_all_items.invoke_arn
            httpMethod = "GET"
            type = "AWS_PROXY"
          }
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        }
      },
      "/item/{id}" = {
        get = {
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.get_item.invoke_arn
            httpMethod = "GET"
            type = "AWS_PROXY"
          }
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        },
        put = {
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.update_item.invoke_arn
            httpMethod = "PUT"
            type = "AWS_PROXY"
          }
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        },
        post = {
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.complete_item.invoke_arn
            httpMethod = "POST"
            type = "AWS_PROXY"
          }
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        },
        delete = {
          x-amazon-apigateway-integration = {
            uri = aws_lambda_function.delete_item.invoke_arn
            httpMethod = "DELETE"
            type = "AWS_PROXY"
          }
          responses = {
            "200" = {
              description = "200 response"
            }
          }
        }
      }
    }
  })

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name         = "${var.stack_name}-auth"
  type         = "COGNITO_USER_POOLS"
  rest_api_id  = aws_api_gateway_rest_api.api.id
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api.body))
  }
  depends_on = [aws_lambda_permission.api_gateway]
}

resource "aws_api_gateway_stage" "stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format          = jsonencode({
      requestId = "$context.requestId",
      ip        = "$context.identity.sourceIp",
      caller    = "$context.identity.caller",
      user      = "$context.identity.user",
      requestTime = "$context.requestTime",
      httpMethod  = "$context.httpMethod",
      resourcePath = "$context.resourcePath",
      status       = "$context.status",
      protocol     = "$context.protocol",
      responseLength = "$context.responseLength"
    })
  }

  xray_tracing_enabled = true

  tags = {
    Name        = "${var.stack_name}-stage"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name = "/aws/api-gateway/${var.stack_name}"

  tags = {
    Name        = "${var.stack_name}-log-group"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "${var.stack_name}-usage-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.stage.stage_name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }

  tags = {
    Name        = "${var.stack_name}-usage-plan"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "add_item" {
  filename         = "path/to/your/lambda.zip"
  function_name    = "${var.stack_name}-add-item"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  memory_size      = 1024
  timeout          = 60
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.todo_table.name
    }
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.add_item.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/prod/*"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.stack_name}-lambda-exec"

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
    Name        = "${var.stack_name}-lambda-exec"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.stack_name}-lambda-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.stack_name}-lambda-policy"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_amplify_app" "frontend" {
  name            = "${var.stack_name}-frontend"
  repository      = var.github_repository
  oauth_token     = var.github_token

  build_spec = <<-EOT
  version: 1
  frontend:
    phases:
      preBuild:
        commands:
          - npm install
      build:
        commands:
          - npm run build
    artifacts:
      baseDirectory: /build
      files:
        - '**/*'
    cache:
      paths:
        - node_modules/**/*
  EOT

  environment_variables = {
    NODE_ENV = "production"
  }

  branch {
    branch_name = "main"
    enable_auto_build = true
  }
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
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "api_gateway_policy" {
  name   = "${var.stack_name}-api-gateway-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.stack_name}-api-gateway-policy"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "api_gateway_policy_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
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
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name   = "${var.stack_name}-amplify-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "amplify:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.stack_name}-amplify-policy"
    Environment = "production"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito User Pool"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB Table"
}

output "api_gateway_url" {
  value       = aws_api_gateway_rest_api.api.execution_arn
  description = "The execution ARN of the API Gateway"
}

output "amplify_app_url" {
  value       = aws_amplify_app.frontend.default_domain
  description = "The default domain of the Amplify App"
}
