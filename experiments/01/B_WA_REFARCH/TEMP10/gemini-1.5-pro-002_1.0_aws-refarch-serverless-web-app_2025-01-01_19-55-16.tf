terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "stack_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "main"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }
  tags = {
    Name        = "${var.project_name}-${var.environment}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_ADMIN_USER_PASSWORD_AUTH"]


  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
  
  tags = {
    Name        = "${var.project_name}-${var.environment}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${var.project_name}-app"
  user_pool_id = aws_cognito_user_pool.main.id
  tags = {
    Name        = "${var.project_name}-${var.environment}-user-pool-domain"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
 read_capacity = 5
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project_name
  }
}




resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-${var.environment}-api"
  description = "API Gateway for ${var.project_name}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
  rest_api_id     = aws_api_gateway_rest_api.main.id
}


resource "aws_api_gateway_resource" "item" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 parent_id   = aws_api_gateway_rest_api.main.root_resource_id
 path_part   = "item"
}

resource "aws_api_gateway_resource" "item_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.item.id
  path_part   = "{id}"
}



resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.environment}-lambda-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
 tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-${var.environment}-lambda-policy"
 policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query"
         ],
      "Resource": "*"
    },
    {
            "Effect": "Allow",
            "Action": [
                "xray:PutTraceSegments",
                "xray:PutTelemetryRecords"
            ],
            "Resource": "*"
        }


  ]
}
EOF
}



resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}



data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir = "../lambda" # Replace with the actual directory of your Lambda function
 output_path = "lambda_function.zip"
}



resource "aws_lambda_function" "add_item" {
  function_name = "${var.project_name}-${var.environment}-add-item-function"
  filename      = data.archive_file.lambda_zip.output_path
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler" # Replace with correct handler
  runtime       = "nodejs12.x" # Replace with the appropriate runtime
 memory_size = 1024
 timeout = 60
 tracing_config {
    mode = "Active"
  }


  tags = {
    Name        = "${var.project_name}-${var.environment}-add-item-function"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create Lambda functions for other operations (get, update, delete, etc.)
# Ensure each Lambda function targets DynamoDB correctly and has correct permissions



resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito.id
}



resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item.id
  http_method             = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"
  credentials = aws_iam_role.lambda_role.arn
 uri = aws_lambda_function.add_item.invoke_arn
}



resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"


 depends_on = [
    aws_api_gateway_integration.post_item_integration, # Add dependencies for other API integrations

  ]
}


resource "aws_api_gateway_usage_plan" "main" {
  name         = "${var.project_name}-${var.environment}-usage-plan"
  description = "Usage plan for ${var.project_name}"

  api_stages {
 api_id = aws_api_gateway_rest_api.main.id
    stage = aws_api_gateway_deployment.main.stage_name
  }


 throttle_settings {
    burst_limit = 100
 rate_limit = 50
  }

 quota_settings {
    limit  = 5000
    period = "DAY"
  }
}



resource "aws_amplify_app" "main" {
  name       = "${var.project_name}-${var.environment}-amplify-app"
  repository = var.github_repo_url
 build_spec = <<YAML
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: /build
    files:
      - '**/*'
YAML

  tags = {
    Name        = "${var.project_name}-${var.environment}-amplify-app"
    Environment = var.environment
    Project     = var.project_name
  }
}




resource "aws_amplify_branch" "main" {

 app_id = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true
  tags = {
    Name        = "${var.project_name}-${var.environment}-amplify-branch"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-${var.environment}-amplify-role"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
  "Statement": [
 {
      "Action": "sts:AssumeRole",
      "Principal": {
 "Service": "amplify.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
 }
  ]
}
EOF

  tags = {
    Name        = "${var.project_name}-${var.environment}-amplify-role"
    Environment = var.environment
    Project     = var.project_name
  }

}


resource "aws_iam_policy" "amplify_policy" {
  name = "${var.project_name}-${var.environment}-amplify_policy"
 policy = <<EOF
{
  "Version": "2012-10-17",
 "Statement": [
    {
      "Sid": "VisualEditor0",
      "Effect": "Allow",
      "Action": "amplify:*",
      "Resource": "*"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "amplify_attach" {
  role = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}




resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"

  retention_in_days = 30
 tags = {
    Name        = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
    Environment = var.environment
    Project     = var.project_name
  }
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

output "api_gateway_url" {
 value = aws_api_gateway_deployment.main.invoke_url
}


output "amplify_app_id" {
 value = aws_amplify_app.main.app_id
}


output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}

