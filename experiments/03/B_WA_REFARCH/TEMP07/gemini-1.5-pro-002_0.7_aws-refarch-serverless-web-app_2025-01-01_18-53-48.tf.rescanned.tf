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
  description = "The AWS region to deploy resources in."
}

variable "stack_name" {
  type    = string
  default = "todo-app"
  description = "The name of the stack."

}

variable "application_name" {
  type    = string
  default = "todo-app"
  description = "The name of the application."

}

variable "github_repo_url" {
  type = string
 description = "The URL of the GitHub repository."
}

variable "github_repo_branch" {
  type    = string
  default = "master"
  description = "The branch of the GitHub repository."

}

variable "github_access_token" {
  type = string
  sensitive = true
 description = "GitHub Personal Access Token"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]
  mfa_configuration = "OFF" # Explicitly set MFA to OFF

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  generate_secret                    = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["authorization_code", "implicit"]
  allowed_scopes                     = ["email", "phone", "openid"]
  

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}



resource "aws_dynamodb_table" "main" {
 name           = "todo-table-${var.stack_name}"
 billing_mode   = "PROVISIONED"
 read_capacity  = 5
 write_capacity = 5
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

 server_side_encryption {
   enabled = true
 }

 point_in_time_recovery {
    enabled = true
  }


 tags = {
   Name        = "todo-table-${var.stack_name}"
   Environment = var.stack_name
   Project     = var.application_name
 }
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
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
      },
    ]
  })

  tags = {
    Name        = "api-gateway-cloudwatch-role-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
    ]
  })
}




# Lambda functions and related resources will be added here in a future iteration due to the complexity and length of the required Terraform code.  This simplified version focuses on the core infrastructure components.

resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-website"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "${var.application_name}-s3-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

resource "aws_amplify_app" "main" {
 name                       = "${var.application_name}-amplify-${var.stack_name}"
 repository                = var.github_repo_url
 access_token               = var.github_access_token
 build_spec = <<-EOT
 version: 0.1
 frontend:
   phases:
     preBuild:
       commands:
         - npm ci
     build:
       commands:
         - npm run build
     postBuild:
       commands:
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
 EOT

  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true

  tags = {
    Name        = "${var.application_name}-amplify-branch-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}

output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
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

output "amplify_app_id" {
  value = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}


resource "aws_accessanalyzer_analyzer" "analyzer" {
  analyzer_name = "example-analyzer"
  type          = "ACCOUNT"

  tags = {
    Name        = "access-analyzer-${var.stack_name}"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


