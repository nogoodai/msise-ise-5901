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

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
 minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }
}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-${random_id.main.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_id" "main" {
  byte_length = 8
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.main.id


  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]


  generate_secret = false


}


resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"


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
    Name = "todo-table-${var.stack_name}"
  }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-api-gateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })
}


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*",
        Effect   = "Allow"
      }
    ]
  })
}





resource "aws_api_gateway_rest_api" "main" {
 name = "${var.stack_name}-api"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body))
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
}


resource "aws_api_gateway_usage_plan" "main" {
  name = "${var.stack_name}-usage-plan"

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

 quota_settings {
    limit  = 5000
    period = "DAY"
  }
}


resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.stack_name}-lambda-role"
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
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "${var.stack_name}-lambda-dynamodb-policy"
  description = "Policy for Lambda to access DynamoDB"
  policy = jsonencode({
    Version = "2012-10-17",
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
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_dynamodb_attachment" {
  name       = "${var.stack_name}-lambda-dynamodb-attachment"
  roles      = [aws_iam_role.lambda_exec_role.name]
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
 name = "${var.stack_name}-lambda-cloudwatch-policy"
  policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
 "cloudwatch:PutMetricData"
        ],
        Resource = "*",
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_cloudwatch_attachment" {
  name       = "${var.stack_name}-lambda-cloudwatch-attachment"
 roles      = [aws_iam_role.lambda_exec_role.name]
 policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}


resource "aws_amplify_app" "main" {
  name       = var.stack_name
 repository = var.github_repo
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub personal access token
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
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

output "api_gateway_url" {
  value = aws_api_gateway_rest_api.main.execution_arn
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}
