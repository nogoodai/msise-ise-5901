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
  type        = string
  description = "The AWS region to deploy the resources in."
  default     = "us-east-1"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "serverless-todo-app"
}

variable "application_name" {
  type        = string
  description = "The application name"
  default     = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
  default     = "your-github-repo"
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository to use."
  default     = "master"

}

variable "github_access_token" {
  type        = string
  description = "GitHub access token."
  sensitive   = true
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"


 email_verification_message = "Your verification code is {####}"
  verification_message_template {
    sms_message = "Your verification code is {####}"
  }

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]

  mfa_configuration = "OFF"
 tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

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
  billing_mode = "PAY_PER_REQUEST"

 server_side_encryption {
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
 point_in_time_recovery {
 enabled = true
 }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}




resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"

 minimum_compression_size = 0

  tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }


}



resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
 xray_tracing_enabled = true

  tags = {
    Name        = "prod"
    Environment = "prod"
    Project     = var.application_name
  }
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



resource "aws_api_gateway_usage_plan" "main" {
  name            = "${var.application_name}-usage-plan-${var.stack_name}"
  description     = "Usage plan for ${var.application_name} API"
  product_code    = "prod"
  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
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
    Name        = "${var.application_name}-usage-plan-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



resource "aws_lambda_function" "add_item" {
# ... (Lambda function configurations)
tracing_config {
      mode = "Active"
    }

 tags = {
    Name        = "add_item"
    Environment = "prod"
    Project     = var.application_name
  }
}

# ... (Other Lambda functions - get_item, get_all_items, update_item, complete_item, delete_item)


resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-bucket-${var.stack_name}"
  acl    = "private"


  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "${var.application_name}-bucket-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}


resource "aws_amplify_app" "main" {
 name = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo
 access_token = var.github_access_token
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
     postBuild:
       commands:
         - aws s3 sync build s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF

 tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
 }
}


resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
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
    Environment = "prod"
    Project     = var.application_name
  }
}

# ... (Other IAM roles and policies)


# Outputs

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

# ... (Other outputs)
