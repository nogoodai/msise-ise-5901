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
  default = "us-west-2"
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

variable "github_branch_name" {
  type    = string
  default = "master"
}




resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }
  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                = ["phone", "email", "openid"]

 callback_urls = ["http://localhost:8000"] # Replace with your callback URLs
  logout_urls = ["http://localhost:8000"] # Replace with your logout URLs

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
    Environment = var.environment
 Project     = var.project_name
  }
}


resource "aws_cognito_user_pool_domain" "main" {
 domain      = "${var.project_name}-${var.environment}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-domain"
    Environment = var.environment
    Project     = var.project_name
  }

}



resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
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


  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
 Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-role"

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
 Name        = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-role"
 Environment = var.environment
    Project     = var.project_name
 }
}



resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-api-gateway-cw-logs-policy"
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
 name        = "${var.project_name}-${var.environment}-${var.stack_name}-api"

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-api"
    Environment = var.environment
 Project     = var.project_name
  }
}


resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "${var.project_name}-${var.environment}-${var.stack_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns  = [aws_cognito_user_pool.main.arn]
  type           = "COGNITO_USER_POOLS"
  authorizer_credentials = aws_iam_role.api_gateway_role.arn
}


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
 tags = {
 Name = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-role"
 Environment = var.environment
 Project = var.project_name
 }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-dynamodb-policy"

 policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowDynamoDBAccess",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "${aws_dynamodb_table.main.arn}"
        }
    ]
}
EOF


}


resource "aws_iam_policy_attachment" "lambda_dynamodb_policy_attachment" {
 name       = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-dynamodb-attachment"
 policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
 roles      = [aws_iam_role.lambda_role.name]
}



resource "aws_iam_policy" "lambda_cloudwatch_policy" {
 name = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-cw-policy"
 policy = <<EOF
{
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
}

EOF
}


resource "aws_iam_policy_attachment" "lambda_cloudwatch_policy_attachment" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-lambda-cloudwatch-attachment"
 policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
 roles      = [aws_iam_role.lambda_role.name]

}



data "archive_file" "lambda_zip" {
 type        = "zip"
 source_dir = "../lambda-functions/" # Replace with your Lambda functions directory
 output_path = "lambda_functions.zip"

}


resource "aws_lambda_function" "add_item" {
 filename         = data.archive_file.lambda_zip.output_path
  function_name = "${var.project_name}-${var.environment}-${var.stack_name}-add-item"
 role            = aws_iam_role.lambda_role.arn
 handler         = "add-item.handler" # Replace with your handler
 runtime         = "nodejs12.x"
 memory_size    = 1024
 timeout         = 60


  tags = {
 Name        = "${var.project_name}-${var.environment}-${var.stack_name}-add-item"
 Environment = var.environment
 Project     = var.project_name
  }
}


# Create similar resources for other Lambda functions (get_item, get_all_items, update_item, complete_item, delete_item)
# Be sure to adjust handler and function_name accordingly


resource "aws_amplify_app" "main" {
 name       = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url

 build_spec = <<EOF
version: 0.1
frontend:
 phases:
  preBuild:
    commands:
      - npm install
  build:
 commands:
      - npm run build
 artifacts:
 baseDirectory: build
 files:
 - '**/*'
EOF

  tags = {
 Name        = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-app"
 Environment = var.environment
 Project     = var.project_name
 }
}




resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch_name
 enable_auto_build = true


  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-branch"
    Environment = var.environment
 Project = var.project_name
 }
}

resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-role"

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
 Name = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-role"
    Environment = var.environment
    Project = var.project_name
  }
}



# ... (API Gateway resources, methods, integrations, stages, usage plan, documentation)

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
  value = aws_api_gateway_rest_api.main.id
 # Note: You'll need to construct the full URL including the stage name
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id

}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain

}


