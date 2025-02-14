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
  type        = string
  default     = "us-west-2"
  description = "The AWS region to deploy the resources to."
}

variable "stack_name" {
  type        = string
  default     = "todo-app"
  description = "The name of the stack."
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_branch" {
  type        = string
  default     = "master"
  description = "The branch of the GitHub repository."
}

variable "application_name" {
  type        = string
  description = "The name of the application."
}

variable "github_access_token" {
  type        = string
  sensitive   = true
  description = "GitHub personal access token with appropriate permissions."
}

variable "callback_urls" {
 type = list(string)
  description = "List of callback URLs for the Cognito User Pool Client."

}
variable "logout_urls" {
 type = list(string)
 description = "List of logout URLs for the Cognito User Pool Client."

}

variable "api_key_required" {
  type = bool
  default = true
  description = "Whether API key is required for API Gateway methods."
}



# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"
  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }

 username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration = "OFF" # Consider changing to "ON" or "OPTIONAL" for production



  password_policy {
    minimum_length    = 6
 require_lowercase = true
 require_uppercase = true

  }
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

 callback_urls        = var.callback_urls
 logout_urls          = var.logout_urls
 supported_identity_providers = ["COGNITO"]

}



# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PAY_PER_REQUEST"
  server_side_encryption {
    enabled = true
  }

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

 point_in_time_recovery {
 enabled = true
 }

  tags = {
    Name = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }


}


# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"
 tags = {
    Name        = "lambda-role-${var.stack_name}"
 Environment = "prod"
 Project = var.application_name
  }
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda functions to access DynamoDB and CloudWatch
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
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
 "cloudwatch:PutMetricData"

        ],
 Effect   = "Allow",
 Resource = "*"
      },
      {
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
  tags = {
    Name = "lambda-policy-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }
}


# Attach IAM policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda Functions (Placeholder - Replace with your actual Lambda function code)
resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  filename      = "add_item.zip" # Replace with your function's zip file
  handler       = "index.handler" # Replace with your function's handler
 runtime       = "nodejs16.x"
  memory_size  = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
 tracing_config {
    mode = "Active"
  }
 tags = {
    Name = "add-item-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }


}


# Example for other Lambda functions - repeat for other CRUD operations
resource "aws_lambda_function" "get_item" {
 function_name = "get-item-${var.stack_name}"
  filename      = "get_item.zip" # Replace with your function's zip file
  handler       = "index.handler" # Replace with your function's handler
  runtime       = "nodejs16.x"
 memory_size  = 1024
  timeout       = 60
 role          = aws_iam_role.lambda_role.arn
  tracing_config {
 mode = "Active"
 }
  tags = {
    Name = "get-item-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }
}

data "aws_cloudwatch_log_group" "api_gw" {
 name = "/aws/apigateway/${var.stack_name}-api-prod-stage"

}
# API Gateway - REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"
  description = "API Gateway for ${var.stack_name}"

  minimum_compression_size = 0
 tags = {
    Name = "${var.stack_name}-api"
    Environment = "prod"
    Project = var.application_name

  }
}

resource "aws_api_gateway_account" "demo" {
 cloudwatch_role_arn = aws_iam_role.lambda_role.arn
}
# API Gateway - Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito_authorizer"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# API Gateway - Resource and Method (Example - Add Item)
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
 rest_api_id   = aws_api_gateway_rest_api.main.id
 resource_id   = aws_api_gateway_resource.item_resource.id
 http_method   = "POST"
 authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

  api_key_required = var.api_key_required
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
 integration_subtype    = "Event"


  integration_uri = aws_lambda_function.add_item.invoke_arn
}

# API Gateway - Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id


  triggers = {
 redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body))
  }
 lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_method_settings" "settings" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
    logging_level   = "INFO"
 data_trace_enabled = true
  }
}
# API Gateway - Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
 rest_api_id   = aws_api_gateway_rest_api.main.id
 stage_name    = "prod"
  xray_tracing_enabled = true

 access_log_settings {
    destination_arn = data.aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({
      requestId = "$context.requestId",
      ip = "$context.identity.sourceIp",
      caller = "$context.identity.caller",
      user = "$context.identity.user",
      requestTime = "$context.requestTime",
      httpMethod = "$context.httpMethod",
 resourcePath = "$context.resourcePath",
      status = "$context.status",
 protocol = "$context.protocol",
 responseLength = "$context.responseLength",
      integrationErrorMessage = "$context.integrationErrorMessage"
      })



 }
 tags = {
    Name = "prod-stage"
    Environment = "prod"
 Project = var.application_name
  }
}



resource "aws_api_gateway_usage_plan_key" "main" {
 key_id        = "mykeyid"
 key_type      = "API_KEY"
 usage_plan_id = aws_api_gateway_usage_plan.main.id
}
# API Gateway - Usage Plan
resource "aws_api_gateway_usage_plan" "main" {
  name = "usage_plan-${var.stack_name}"
  description = "Usage plan for ${var.stack_name}"

 api_stages {
 api_id = aws_api_gateway_rest_api.main.id
 stage  = aws_api_gateway_stage.prod.stage_name
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
    Name = "usage_plan-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }
}



# Amplify Application
resource "aws_amplify_app" "main" {
 name       = var.application_name
  repository = var.github_repo
  access_token = var.github_access_token

 build_spec = <<-EOT
version: 0.1
frontend:
  phases:
    install:
      commands:
 - npm ci
 preBuild:
 commands:
 - npm run build
 build:
 commands:
 - npm run export
 artifacts:
 baseDirectory: /out
 files:
 - '**/*'
 EOT


}

# Amplify Branch (master branch)
resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
  enable_auto_build = true

}




output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
 description = "The ID of the Cognito User Pool Client."
}

output "dynamodb_table_name" {
 value       = aws_dynamodb_table.main.name
 description = "The name of the DynamoDB table."
}

output "api_gateway_url" {
  value       = aws_api_gateway_deployment.main.invoke_url
  description = "The URL of the API Gateway."
}

output "amplify_app_id" {
 value       = aws_amplify_app.main.id
 description = "The ID of the Amplify application."
}

