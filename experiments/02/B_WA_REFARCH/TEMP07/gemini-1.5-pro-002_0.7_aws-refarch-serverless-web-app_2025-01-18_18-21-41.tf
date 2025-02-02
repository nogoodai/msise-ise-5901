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
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "main"
}

variable "github_repo_access_token" {
  type = string
  sensitive = true
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id


  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000/"] # Placeholder - replace with your actual callback URL
  logout_urls          = ["http://localhost:3000/"] # Placeholder - replace with your actual logout URL
  generate_secret      = false

  prevent_user_existence_errors = "ENABLED"
}


# DynamoDB Table
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


# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.stack_name}-lambda-role"

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

# IAM Policy for Lambda functions to access DynamoDB and CloudWatch
resource "aws_iam_policy" "lambda_policy" {
 name = "${var.stack_name}-lambda-policy"

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
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"

        ],
        Effect = "Allow",
        Resource = "*"
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

}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}




# Placeholder for Lambda function code - replace with your actual code.
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/${var.stack_name}-lambda.zip"
  source_dir  = "./lambda-code" # Replace with your lambda function directory
}

# Lambda Functions (Example - Add Item) - Repeat this for other functions
resource "aws_lambda_function" "add_item" {
  function_name = "${var.stack_name}-add-item"
  handler       = "index.handler"
  runtime       = "nodejs16.x"
  memory_size   = 1024
  timeout       = 60

  role    = aws_iam_role.lambda_role.arn
  filename = data.archive_file.lambda_zip.output_path

  tracing_config {
    mode = "Active"
  }

 environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }
}



# API Gateway Rest API
resource "aws_api_gateway_rest_api" "main" {
 name        = "${var.stack_name}-api"
 description = "API Gateway for ${var.stack_name}"
}


# API Gateway Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id  = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}


# API Gateway Resource and Method (Example - Add Item) - Repeat this for other resources/methods
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito.id

}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype    = "Event"
  integration_uri        = aws_lambda_function.add_item.invoke_arn
}




# API Gateway Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}




# API Gateway Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
}




# IAM Role for API Gateway to write logs to CloudWatch
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-apigw-cw-role"
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
}


resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
 name = "${var.stack_name}-apigw-cw-policy"
  policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
 "logs:PutLogEvents",
 "logs:GetLogEvents",
 "logs:FilterLogEvents"
        ],
        Resource = "*"
      }
    ]
 })
}

resource "aws_iam_role_policy_attachment" "apigw_cw_attach" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}



# Account ID for use in Amplify setup
data "aws_caller_identity" "current" {}

# IAM Role for Amplify
resource "aws_iam_role" "amplify_role" {
  name = "${var.stack_name}-amplify-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
 Service = "amplify.amazonaws.com"
 }
      }
    ]
 })
}

# IAM Policy for Amplify
resource "aws_iam_policy" "amplify_policy" {
  name = "${var.stack_name}-amplify-policy"
  policy = jsonencode({
    Version = "2012-10-17",
 Statement = [
 {
 Effect = "Allow",
 Action = [
 "iam:PassRole"
 ],
 Resource = "*"
 },
      {
        Effect = "Allow",
 Action = "*",
 Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/amplifyconsole-*"
 ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amplify_attach" {
  role       = aws_iam_role.amplify_role.name
  policy_arn = aws_iam_policy.amplify_policy.arn
}


# Amplify App
resource "aws_amplify_app" "main" {
 name       = var.stack_name
 repository = var.github_repo_url
 access_token = var.github_repo_access_token
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

  iam_service_role_arn = aws_iam_role.amplify_role.arn

}


# Amplify Branch (Master Branch)
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

output "api_gateway_invoke_url" {
 value = aws_api_gateway_stage.prod.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}


