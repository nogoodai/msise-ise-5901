terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider aws {
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

variable "application_name" {
  type    = string
  default = "todo-app"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "main" {
  name                      = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id             = aws_cognito_user_pool.main.id

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

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


resource "aws_iam_role" "api_gateway_cloudwatch_logs_role" {
  name = "api-gateway-cloudwatch-logs-${var.stack_name}"

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

resource "aws_iam_role_policy" "api_gateway_cloudwatch_logs_policy" {
 name = "api-gateway-cloudwatch-logs-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_logs_role.id
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "logs:CreateLogGroup",
 "logs:CreateLogStream",
          "logs:PutLogEvents"
 ],
        Effect = "Allow",
        Resource = "*"
      }
    ]
  })
}

# Placeholder resource for Amplify. Full implementation requires specific Amplify resources which are beyond the scope of a generic example.
resource "null_resource" "amplify_placeholder" {
  provisioner "local-exec" {
    command = "echo 'Amplify configuration would be placed here.  See note in code comments.'"
  }
}

# Placeholder resource for Lambda functions.  Lambda function code needs to be uploaded to S3, and specific permissions will depend on the function's functionality.
resource "null_resource" "lambda_placeholder" {
  provisioner "local-exec" {
    command = "echo 'Lambda function configuration would be placed here. See note in code comments.'"
  }
}

# Placeholder resource for API Gateway.  This would involve creating API Gateway resources, methods, integrations, and attaching the Cognito authorizer.
resource "null_resource" "api_gateway_placeholder" {
  provisioner "local-exec" {
    command = "echo 'API Gateway configuration would be placed here. See note in code comments.'"
  }
}



output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_domain" {
  value = aws_cognito_user_pool_domain.domain
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}


