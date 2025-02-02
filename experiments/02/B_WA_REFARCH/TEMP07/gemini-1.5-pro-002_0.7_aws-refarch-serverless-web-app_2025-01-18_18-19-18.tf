terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
 type = string
 default = "main"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  schema {
    attribute_data_type = "String"
    developer_only_attribute = false
    mutable = true
    name = "email"
    required = true
  }
  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  generate_secret = false
  callback_urls = ["http://localhost:3000/"] # Placeholder - replace with your actual callback URL

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5
 server_side_encryption {
 enabled = true
 }

 attribute {
   name = "cognito-username"
   type = "S"
 }
 attribute {
   name = "id"
   type = "S"
 }

 hash_key = "cognito-username"
 range_key = "id"

 tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# IAM Role for API Gateway logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })
  tags = {
    Name        = "api-gateway-cloudwatch-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# IAM Policy for API Gateway logging
resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {

  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
 ],
        Effect = "Allow",
 Resource = "*"
      },
    ]
  })
}


# Attach IAM Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
 Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# IAM Policy for Lambda (DynamoDB and CloudWatch)

resource "aws_iam_policy" "lambda_policy" {
  name = "lambda-policy-${var.stack_name}"
  policy = jsonencode({
 Version = "2012-10-17",
 Statement = [
      {
        Action = [
 "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
 "dynamodb:Scan", # Added scan for get all items
 "dynamodb:Query"
 ],
 Effect = "Allow",
 Resource = aws_dynamodb_table.main.arn
 },
 {
 Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
 ],
        Effect = "Allow",
 Resource = "*"
      },
      {
        Action = [
 "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
 ],
        Effect   = "Allow",
        Resource = "*"
      }
 ]
  })
}

# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_policy.arn
}


# Placeholder for Lambda functions - replace with your actual Lambda function code
resource "aws_lambda_function" "lambda_functions" {
 for_each = {
 "add_item"    = { handler = "index.handler", memory = 1024, timeout = 60, api_path = "/item", api_method = "POST" },
 "get_item"    = { handler = "index.handler", memory = 1024, timeout = 60, api_path = "/item/{id}", api_method = "GET" },
 "get_all_items" = { handler = "index.handler", memory = 1024, timeout = 60, api_path = "/item", api_method = "GET" },
        "update_item"   = { handler = "index.handler", memory = 1024, timeout = 60, api_path = "/item/{id}", api_method = "PUT" },
        "complete_item" = { handler = "index.handler", memory = 1024, timeout = 60, api_path = "/item/{id}/done", api_method = "POST" },
 "delete_item"  = { handler = "index.handler", memory = 1024, timeout = 60, api_path = "/item/{id}", api_method = "DELETE" }
  }

 filename      = "lambda_function.zip" # Replace with your Lambda function zip file
 function_name = "${var.application_name}-${each.key}-${var.stack_name}"
 handler       = each.value.handler
 memory_size   = each.value.memory
 timeout       = each.value.timeout
 role          = aws_iam_role.lambda_role.arn
 runtime       = "nodejs12.x" # Replace with desired runtime
 tracing_config {
 mode = "Active"
 }
 source_code_hash = filebase64sha256("lambda_function.zip")

 tags = {
    Name        = "${var.application_name}-${each.key}-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# API Gateway (REST API)
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"

  tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 stage_name  = "prod"
 depends_on = [
 aws_api_gateway_integration.lambda_integrations
 ]
}


# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
 deployment_id = aws_api_gateway_deployment.main.id
 rest_api_id   = aws_api_gateway_rest_api.main.id
 stage_name    = "prod"
 }


# API Gateway Integrations for Lambda functions
resource "aws_api_gateway_integration" "lambda_integrations" {

 for_each = aws_lambda_function.lambda_functions

 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.proxy.id
 http_method = each.value.api_method
 integration_http_method = "POST"
 type                    = "aws_proxy"
 integration_subtype = "Event"
 credentials = aws_iam_role.lambda_role.arn
 request_templates = {
 "application/json" = jsonencode({statusCode = 200})
 }
 integration_response {
   status_code = "200"
 }

}


resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "{proxy+}"
}



# Amplify App
resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo
 access_token = var.github_access_token # Set via environment variable for security
 build_spec = <<EOF
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
   baseDirectory: build
   files:
 - '**/*'
 cache:
 paths:
   - node_modules/**/*
EOF
 tags = {
    Name = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# Amplify Branch - master branch
resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true

 tags = {
    Name = "${var.application_name}-amplify-branch-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
 value = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}


