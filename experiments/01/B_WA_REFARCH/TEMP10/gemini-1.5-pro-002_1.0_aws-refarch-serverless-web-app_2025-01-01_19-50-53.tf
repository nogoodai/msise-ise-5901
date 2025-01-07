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

variable "github_branch" {
  type    = string
  default = "master"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                         = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
  user_pool_id                 = aws_cognito_user_pool.main.id
  generate_secret              = false
  explicit_auth_flows         = ["ADMIN_NO_SRP_AUTH", "AUTHORIZATION_CODE", "IMPLICIT"]
  supported_identity_providers = ["COGNITO"]
  allowed_oauth_flows          = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes        = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }

}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.environment}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-domain"
    Environment = var.environment
    Project     = var.project_name
  }
}


# DynamoDB Table
resource "aws_dynamodb_table" "main" {
 name         = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
 read_capacity = 5
 write_capacity = 5
 hash_key      = "cognito-username"
 range_key     = "id"
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


# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-role"

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
}


# IAM Policy for Lambda functions - DynamoDB access
resource "aws_iam_policy" "lambda_dynamodb_policy" {

  name = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-dynamodb-policy"

 policy = jsonencode({
   Version = "2012-10-17"
   Statement = [
     {
       Effect = "Allow",
       Action = [
         "dynamodb:GetItem",
         "dynamodb:PutItem",
         "dynamodb:UpdateItem",
         "dynamodb:DeleteItem",
         "dynamodb:BatchGetItem",
         "dynamodb:BatchWriteItem",
         "dynamodb:Query",
         "dynamodb:Scan"

       ],
       Resource = aws_dynamodb_table.main.arn
     },
     {
       Effect = "Allow",
       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents"
       ],
       Resource = "arn:aws:logs:*:*:*"
     },
     {
       Effect = "Allow",
       Action = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
       ],
       Resource = "*"
     }
   ]

 })
}

# Attach the policy to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



# API Gateway REST API

resource "aws_apigatewayv2_api" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-api"
  protocol_type = "HTTP"


 tags = {
   Name = "${var.project_name}-${var.environment}-${var.stack_name}-api"
   Environment = var.environment
   Project = var.project_name
 }
}




# API Gateway Stage
resource "aws_apigatewayv2_stage" "prod" {
 api_id = aws_apigatewayv2_api.main.id
 name   = "prod"

 access_log_settings {
   destination_arn = aws_cloudwatch_log_group.api_gw.arn
   format = jsonencode({
     requestId = "$context.requestId",
     ip       = "$context.identity.sourceIp",
     caller  = "$context.identity.caller",
     user    = "$context.identity.user",
     requestTime = "$context.requestTime",
     httpMethod = "$context.httpMethod",
     resourcePath = "$context.resourcePath",
     status = "$context.status",
     protocol = "$context.protocol",
     responseLength = "$context.responseLength"
   })

 }

 tags = {
   Name = "${var.project_name}-${var.environment}-${var.stack_name}-api-stage"
   Environment = var.environment
   Project = var.project_name
 }
}

# API Gateway Usage Plan
resource "aws_apigatewayv2_usage_plan" "main" {
 name = "${var.project_name}-${var.environment}-${var.stack_name}-usage-plan"


 api_stages {
   api_id = aws_apigatewayv2_api.main.id
   stage  = aws_apigatewayv2_stage.prod.name
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
   Name = "${var.project_name}-${var.environment}-${var.stack_name}-api-usage-plan"
   Environment = var.environment
   Project = var.project_name
 }


}

#  CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/apigateway/${aws_apigatewayv2_api.main.name}-access-logs"


  tags = {
    Name = "${var.project_name}-${var.environment}-${var.stack_name}-api-logs"
    Environment = var.environment
    Project = var.project_name
 }
}


# IAM Role for API Gateway to write logs to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-cloudwatch-role"

 assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Action": "sts:AssumeRole",
   "Principal": {
    "Service": "apigateway.amazonaws.com"
   },
   "Effect": "Allow",
   "Sid": ""
  }
 ]
}
EOF

}

# IAM Policy for API Gateway to write logs to CloudWatch
resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {

 name = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-cloudwatch-policy"


 policy = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
   {
    "Effect": "Allow",
    "Action": [
     "logs:CreateLogGroup",
     "logs:CreateLogStream",
     "logs:DescribeLogGroups",
     "logs:DescribeLogStreams",
     "logs:PutLogEvents",
     "logs:GetLogEvents",
     "logs:FilterLogEvents"
    ],
    "Resource": "*"
   }
  ]
 })

}

# Attach the policy to the API Gateway role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
 role       = aws_iam_role.api_gateway_cloudwatch_role.name
 policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}

# Amplify App
resource "aws_amplify_app" "main" {
 name       = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url

 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with a suitable method for managing secrets

 build_spec = <<EOF
version: 0.1
frontend:
 phases:
   preBuild:
     npm ci
   build:
     npm run build
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF


 tags = {
   Name = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-app"
   Environment = var.environment
   Project = var.project_name
 }
}


# Amplify Branch
resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true



 tags = {
   Name = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-branch"
   Environment = var.environment
   Project = var.project_name
 }
}


# Outputs

output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
 value = aws_apigatewayv2_api.main.id
}


output "amplify_app_id" {
 value = aws_amplify_app.main.id
}



