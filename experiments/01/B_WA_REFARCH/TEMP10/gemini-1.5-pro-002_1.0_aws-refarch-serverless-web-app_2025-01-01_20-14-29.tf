terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
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

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "environment_name" {
  type    = string
  default = "dev"
}

variable "stack_name" {
  type = string
}


# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.environment_name}"
  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
 minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
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
    Name        = "${var.application_name}-cognito-user-pool"
    Environment = var.environment_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name             = "${var.application_name}-app-client"
  user_pool_id    = aws_cognito_user_pool.main.id
  generate_secret = false
  explicit_auth_flows       = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  allowed_oauth_flows       = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]


  tags = {
    Name        = "${var.application_name}-cognito-user-pool-client"
    Environment = var.environment_name
    Project     = var.application_name
  }
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

  tags = {
    Name        = "${var.application_name}-dynamodb-table"
    Environment = var.environment_name
    Project     = var.application_name
  }
}


# IAM Roles and Policies
resource "aws_iam_role" "api_gateway_cw_logs_role" {
  name = "${var.application_name}-api-gateway-cw-logs-role"
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
    Name        = "${var.application_name}-api-gateway-cw-logs-role"
    Environment = var.environment_name
    Project     = var.application_name
  }
}


resource "aws_iam_role_policy" "api_gateway_cw_logs_policy" {
 name = "${var.application_name}-api-gateway-cw-logs-policy"
  role = aws_iam_role.api_gateway_cw_logs_role.id
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
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




