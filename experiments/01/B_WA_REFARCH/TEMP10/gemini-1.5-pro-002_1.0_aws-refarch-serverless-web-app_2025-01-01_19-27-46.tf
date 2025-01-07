terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "github_repo_url" {
  type    = string
  default = "https://github.com/your-username/your-repo" # Replace with your GitHub repository URL
}

variable "github_repo_branch" {
  type    = string
  default = "main"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_client" "main" {
  name                = "${var.stack_name}-user-pool-client"
  user_pool_id        = aws_cognito_user_pool.main.id
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  generate_secret     = false
  allowed_oauth_flows_user_pool_client = true
 allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "phone", "openid"]


}



resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.stack_name}-auth-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}



resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
 hash_key = "cognito-username"
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
      },
    ]
  })
}


resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_logs" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}



resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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

resource "aws_iam_policy" "lambda_dynamodb_policy" {


  name = "${var.stack_name}-lambda-dynamodb-policy"
 policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
 "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
 "dynamodb:Query",
 "dynamodb:Scan"

        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
 "logs:CreateLogStream",
          "logs:PutLogEvents",
 "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
 })


}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


resource "aws_lambda_function" "add_item_function" {

  filename                = "./lambda_functions/add_item.zip" # Replace with your Lambda function code
  function_name = "${var.stack_name}-add-item"
  role                 = aws_iam_role.lambda_role.arn
  handler              = "index.handler" # Replace with your handler name
  source_code_hash      = filebase64sha256("./lambda_functions/add_item.zip")
  runtime             = "nodejs12.x"
 memory_size           = 1024
  timeout              = 60
  tracing_config {
    mode = "Active"
  }
}



resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.stack_name}-api"
  description = "API Gateway for serverless todo app"
}


resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_resource" "item_id_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
 parent_id   = aws_api_gateway_resource.item_resource.id
 path_part   = "{id}"
}


resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"
  credentials = aws_iam_role.lambda_role.arn
  request_templates = {
    "application/json" = jsonencode({statusCode : 200})
 }
  integration_uri = aws_lambda_function.add_item_function.invoke_arn # Example Lambda function ARN
}


resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "${var.stack_name}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
 provider_arns  = [aws_cognito_user_pool.main.arn]
}


resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body))
  }

  lifecycle {
 create_before_destroy = true
  }

 depends_on = [
    aws_api_gateway_integration.post_item_integration, # Include all integrations
 aws_api_gateway_method.post_item, # Include all methods

  ]
}


resource "aws_api_gateway_stage" "prod" {
  stage_name        = "prod"
  rest_api_id      = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
}

resource "aws_api_gateway_usage_plan" "main" {
 name         = "${var.stack_name}-usage-plan"
  description = "Usage plan for the serverless todo app"

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  quota_settings {
    limit  = 5000
    period = "DAY"
  }
}


resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo_url

  build_spec = <<-EOT
version: 0.1
frontend:
 phases:
   preBuild:
     commands:
       - npm install
   build:
     commands:
 - npm run build # Or your build command
 artifacts:
   baseDirectory: build # Or your build directory
   files:
     - '**/*'
cache:
 paths:
   - node_modules/**/*
EOT

}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true

}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}


output "api_gateway_invoke_url" {

 value = aws_api_gateway_deployment.main.invoke_url
}
