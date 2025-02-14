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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The name of the application."
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "master"
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token."
  sensitive   = true
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

 username_attributes      = ["email"]
  mfa_configuration = "OFF" # Consider enforcing MFA for enhanced security


  password_policy {
    minimum_length = 8 # Increased minimum length for stronger passwords
    require_lowercase = true
    require_uppercase = true
    require_numbers = true # Enforce numeric characters
 require_symbols = true # Enforce symbol characters
  }

  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify your email"

 verification_message_template {
    default_email_options {
      sms_verification_message = "Your verification code is {####}"
    }
  }


 auto_verified_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}



# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Update with your callback URL
  logout_urls          = ["http://localhost:3000/"] # Update with your logout URL
  supported_identity_providers = ["COGNITO"]
 prevent_user_existence_errors = "ENABLED"


  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
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
  billing_mode   = "PAY_PER_REQUEST" # Use pay per request for cost optimization

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
 point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-${var.stack_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
 Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-role"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# IAM Policy for Lambda function (DynamoDB access)

resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "${var.application_name}-${var.stack_name}-lambda-dynamodb-policy"


  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowDynamoDBAccess",
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
 "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem"

 ],
        "Resource" : aws_dynamodb_table.main.arn
      }
    ]
  })

 tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-dynamodb-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }


}



resource "aws_iam_policy_attachment" "lambda_dynamodb_attachment" {
  name       = "${var.application_name}-${var.stack_name}-lambda-dynamodb-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


# IAM Policy for Lambda function (CloudWatch Logs access)
resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name = "${var.application_name}-${var.stack_name}-lambda-cloudwatch-policy"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
        "Resource" : "arn:aws:logs:*:*:*",
        "Effect" : "Allow"
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-lambda-cloudwatch-policy"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_policy_attachment" "lambda_cloudwatch_attachment" {
  name       = "${var.application_name}-${var.stack_name}-lambda-cloudwatch-attachment"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}


# Lambda Function (Example: Add Item) - Replace with your Lambda function code
resource "aws_lambda_function" "add_item_function" {
  function_name = "${var.application_name}-${var.stack_name}-add-item-function"
  handler = "index.handler" # Replace with your handler
  runtime = "nodejs16.x" # Updated runtime for latest Node.js version
 memory_size = 1024
  timeout = 60

  role    = aws_iam_role.lambda_role.arn

# Replace with your actual Lambda function code
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
 tracing_config {
    mode = "Active"
  }
 tags = {
    Name        = "${var.application_name}-${var.stack_name}-add-item-function"
    Environment = var.stack_name
    Project     = var.application_name
  }

}



# API Gateway - REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
 minimum_compression_size = 0 # Enable compression

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# API Gateway - Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}


# API Gateway - Resource (Example: /item)
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

# API Gateway - Method (Example: POST /item)
resource "aws_api_gateway_method" "post_item_method" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.item_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
 api_key_required = true
}

# API Gateway - Integration (Example: POST /item)
resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.post_item_method.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
 integration_subtype = "Event"
  credentials = aws_iam_role.lambda_role.arn

 integration_method = "POST"
 request_templates = {
    "application/json" = <<EOF
{
  "statusCode" : 200
}
EOF
  }
  request_parameters = {
    "integration.request.path.id" = "method.request.path.id"
  }
}


data "aws_iam_policy_document" "api_gw_cw_logging" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role_policy" "api_gw_cw_logging" {
  name = "api_gw_cw_logging"
  role = aws_api_gateway_rest_api.main.execution_arn
 policy = data.aws_iam_policy_document.api_gw_cw_logging.json
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

 depends_on = [aws_iam_role_policy.api_gw_cw_logging]
}

# API Gateway - Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
 stage_name    = "prod"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({
      "requestId" : "$context.requestId",
      "ip" : "$context.identity.sourceIp",
      "caller" : "$context.identity.caller",
      "user" : "$context.identity.user",
      "userArn" : "$context.identity.userArn",
      "requestTime" : "$context.requestTime",
 "httpMethod" : "$context.httpMethod",
      "resourcePath" : "$context.resourcePath",
      "status" : "$context.status",
      "protocol" : "$context.protocol",
      "responseLength" : "$context.responseLength"
    })
  }



 xray_tracing_enabled = true

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-stage-prod"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api-gateway/${aws_api_gateway_rest_api.main.name}"
  retention_in_days = 30
}




# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo
  access_token = var.github_access_token
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
    Name        = "${var.application_name}-${var.stack_name}-amplify-app"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

# Amplify Branch - Master
resource "aws_amplify_branch" "master" {
 app_id = aws_amplify_app.main.id
  branch_name = var.github_branch
 enable_auto_build = true


  tags = {
    Name        = "${var.application_name}-${var.stack_name}-amplify-branch-master"
    Environment = var.stack_name
    Project     = var.application_name
  }
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
  description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
 value       = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}

