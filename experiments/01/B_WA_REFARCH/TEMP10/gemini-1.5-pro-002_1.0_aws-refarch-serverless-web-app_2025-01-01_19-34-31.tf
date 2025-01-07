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
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "todo-app"
}

variable "stack_name" {
  type    = string
  default = "todo-app-stack"

}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
 type = string
 default = "main"
}




resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.environment}"

  password_policy {
    minimum_length                   = 6
    require_lowercase               = true
    require_numbers                 = false
    require_symbols                 = false
    require_uppercase               = true
    temporary_password_validity_days = 7
  }

 username_attributes = ["email"]
 auto_verified_attributes = ["email"]


  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.project_name}-user-pool-client-${var.environment}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                   = false
 allowed_oauth_flows_user_pool_client = true
 allowed_oauth_flows = ["authorization_code", "implicit"]
 allowed_oauth_scopes = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"]
  logout_urls          = ["http://localhost:3000/"]
  prevent_user_existence_errors = "ENABLED"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.stack_name}-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
  hash_key       = "cognito-username"
  range_key      = "id"
 read_capacity  = 5
  write_capacity = 5

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
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-role-${var.environment}"

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

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.environment}"
  role = aws_iam_role.api_gateway_role.id

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
      "Resource": "*"
    }
  ]
}
EOF
}



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api-${var.environment}"
 description = "API Gateway for ${var.project_name}"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}





resource "aws_lambda_function" "add_item_function" {

 filename      = var.lambda_zip_file
 function_name = "add_item_function-${var.environment}"
 handler       = "index.handler"
 role          = aws_iam_role.lambda_exec_role.arn
 runtime = "nodejs16.x" # Or your desired runtime

 memory_size = 1024
 timeout = 30

 tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }


  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

 depends_on = [aws_iam_role_policy_attachment.lambda_dynamodb_policy]

}

# ... (similar resources for other Lambda functions)



resource "aws_iam_role" "lambda_exec_role" {
 name = "lambda_exec_role_${var.environment}"

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
  Environment = var.environment
  Project     = var.project_name
 }
}



resource "aws_iam_policy" "lambda_dynamodb_policy" {

 name = "lambda_dynamodb_policy_${var.environment}"


 policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Effect": "Allow",
   "Action": [
    "dynamodb:PutItem",
    "dynamodb:GetItem",
    "dynamodb:UpdateItem",
    "dynamodb:DeleteItem",
    "dynamodb:Scan"

   ],
   "Resource": "${aws_dynamodb_table.main.arn}"
  }
 ]
}
EOF

}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_policy" {
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
 role       = aws_iam_role.lambda_exec_role.name
}


resource "aws_iam_policy" "lambda_cloudwatch_policy" {

 name = "lambda_cloudwatch_policy_${var.environment}"


 policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
          "cloudwatch:PutMetricData"

        ],
          "Resource": "*"

      }
    ]
  })


}



resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_policy" {
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
 role       = aws_iam_role.lambda_exec_role.name
}



variable "lambda_zip_file" {
 type = string
}



# ... (API Gateway resources, methods, integrations, authorizer, stages, and usage plan)

resource "aws_amplify_app" "main" {
  name       = "${var.project_name}-amplify-${var.environment}"
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
  baseDirectory: /build
  files:
   - '**/*'
EOF
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
 enable_auto_build = true


}


variable "github_access_token" {

 type = string
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
 # value = aws_api_gateway_deployment.main.invoke_url
}


output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}

