terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider aws {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-west-2"
  description = "The AWS region to deploy the resources in."
}

variable "stack_name" {
  type    = string
  default = "todo-app"
  description = "The name of the stack."
}

variable "application_name" {
  type    = string
  default = "todo-app"
  description = "The application name"
}

variable "github_repo_url" {
  type = string
  description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type    = string
  default = "main"
  description = "The branch of the Github Repository"

}

variable "github_access_token" {
  type = string
  description = "GitHub personal access token with appropriate permissions."
  sensitive = true
}

variable "callback_urls" {
  type    = list(string)
  description = "List of callback URLs for the Cognito User Pool Client."
}

variable "logout_urls" {
  type    = list(string)
  description = "List of logout URLs for the Cognito User Pool Client."
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
  mfa_configuration = "OFF" # Explicit MFA configuration

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls        = var.callback_urls
  logout_urls          = var.logout_urls
  supported_identity_providers = ["COGNITO"]


}

resource "aws_cognito_user_pool_domain" "main" {
  domain             = "${var.application_name}-${var.stack_name}"
  user_pool_id      = aws_cognito_user_pool.main.id
}



resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5
 server_side_encryption {
   enabled = true
 }
 point_in_time_recovery {
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

  tags = {
    Name = "todo-table-${var.stack_name}"
    Environment = "prod"
 Project = var.application_name
  }
}




data "aws_kms_alias" "log_group_kms_alias" {
  name = "alias/aws/logs" # Using default AWS KMS alias for CloudWatch Logs
}


resource "aws_iam_role" "api_gateway_role" {
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
      }
    ]
  })
 tags = {
 Name = "api-gateway-cloudwatch-role-${var.stack_name}"
 Environment = "prod"
 Project = var.application_name
 }
}

resource "aws_iam_role_policy" "api_gateway_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

}



resource "aws_iam_role" "lambda_role" {
  name = "lambda-dynamodb-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow"
      }
    ]
  })

 tags = {
  Name = "lambda-dynamodb-role-${var.stack_name}"
  Environment = "prod"
  Project = var.application_name
 }
}


resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "lambda-dynamodb-policy-${var.stack_name}"
 policy = jsonencode({
   Version = "2012-10-17",
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
         "dynamodb:Scan",
         "dynamodb:DescribeTable"
       ],
       Effect = "Allow",
       Resource = aws_dynamodb_table.main.arn
     },
     {
       Action = [
        "cloudwatch:PutMetricData"
       ],
       Effect = "Allow",
       Resource = "*"
     }

   ]

 })
 tags = {
 Name = "lambda-dynamodb-policy-${var.stack_name}"
 Environment = "prod"
  Project = var.application_name
 }
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}


# Placeholder for Lambda functions - replace with actual Lambda function code and configuration
resource "aws_lambda_function" "example_lambda" {
  function_name = "example-lambda-${var.stack_name}"
  handler = "index.handler" # Update with your Lambda handler
  role = aws_iam_role.lambda_role.arn
  runtime = "nodejs12.x" # Update with your desired runtime
  memory_size = 1024
  timeout = 60
  tracing_config {
    mode = "Active"
  }

  # Replace with your actual Lambda function code
 filename         = "lambda_function.zip" # Replace with path to your zip file
 source_code_hash = filebase64sha256("lambda_function.zip") # Replace with path to your zip file

 tags = {
  Name = "example-lambda-${var.stack_name}"
  Environment = "prod"
  Project = var.application_name
 }
}


resource "aws_apigatewayv2_api" "main" {
  name          = "api-${var.stack_name}"
  protocol_type = "HTTP"

  tags = {
    Name = "api-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }
}


resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({
      requestId = "$context.requestId",
      ip        = "$context.identity.sourceIp",
      requestTime = "$context.requestTime",
      httpMethod = "$context.httpMethod",
      routeKey = "$context.routeKey",
      status = "$context.status",
      protocol = "$context.protocol",
      responseLength = "$context.responseLength"
    })
  }
 tags = {
 Name = "prod"
 Environment = "prod"
 Project = var.application_name
 }
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/apigateway/${aws_apigatewayv2_api.main.name}"
  retention_in_days = 30
 kms_key_id = data.aws_kms_alias.log_group_kms_alias.target_key_arn
 tags = {
  Name = "/aws/apigateway/${aws_apigatewayv2_api.main.name}"
  Environment = "prod"
  Project = var.application_name
 }
}


resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.main.id
  integration_type = "aws_proxy"
  integration_uri = aws_lambda_function.example_lambda.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}



resource "aws_apigatewayv2_route" "example_route" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /example"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}"
  repository = var.github_repo_url
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
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
}


output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
 description = "The ID of the Cognito User Pool Client."
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
 description = "The name of the DynamoDB table."
}


output "api_gateway_url" {
 value = aws_apigatewayv2_api.main.api_endpoint
 description = "The URL of the API Gateway."
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
 description = "The ID of the Amplify App."
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
 description = "The default domain of the Amplify App."
}


