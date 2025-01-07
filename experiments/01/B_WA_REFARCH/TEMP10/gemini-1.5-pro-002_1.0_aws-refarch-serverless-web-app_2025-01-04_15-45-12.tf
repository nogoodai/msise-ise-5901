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
  type    = string
  default = "serverless-todo-app"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "stack_name" {
  type    = string
  default = "dev-serverless-todo-stack"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name = "${var.project_name}-user-pool-${var.stack_name}"
    Environment = var.environment
    Project = var.project_name

  }
}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.project_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  tags = {
    Name = "${var.project_name}-user-pool-client-${var.stack_name}"
    Environment = var.environment
    Project = var.project_name

  }

}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name = "${var.project_name}-user-pool-domain-${var.stack_name}"
    Environment = var.environment
    Project = var.project_name

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
    Name = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project = var.project_name

  }
}




resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "${var.project_name}-api-gateway-cw-logs-${var.stack_name}"

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
    Name = "${var.project_name}-api-gateway-cw-logs-${var.stack_name}"
    Environment = var.environment
    Project = var.project_name

  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
 name = "${var.project_name}-api-gateway-cw-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs_role.id
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




# Placeholder for API Gateway (requires more specific API definitions)
# Lambda functions (require function code) and IAM roles/policies for Lambda
# Amplify app (requires GitHub repository details and build specifications)



output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}



