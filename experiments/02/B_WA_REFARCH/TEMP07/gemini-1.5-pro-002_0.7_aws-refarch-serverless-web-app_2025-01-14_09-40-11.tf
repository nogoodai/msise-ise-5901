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

variable "stack_name" {
  type = string
}

variable "application_name" {
 type = string
}


variable "github_repository" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]
  username_attributes = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                        = ["http://localhost:3000"] # Placeholder, update as needed
  logout_urls                          = ["http://localhost:3000"] # Placeholder, update as needed
  supported_identity_providers        = ["COGNITO"]
  prevent_user_existence_errors = "ENABLED"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.stack_name
    Project     = var.application_name
  }

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

 server_side_encryption {
   enabled = true
 }

 attribute {
   name = "cognito-username"
   type = "S"
 }

 attribute {
   name = "id"
   type = "S"
 }

 hash_key = "cognito-username"
 range_key = "id"

 tags = {
   Name        = "todo-table-${var.stack_name}"
   Environment = var.stack_name
   Project     = var.application_name
 }
}





resource "aws_iam_role" "api_gateway_cw_logs_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Sid    = "",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      },
    ]
  })

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-role"
    Environment = var.stack_name
    Project     = var.application_name
 }
}


resource "aws_iam_role_policy" "api_gateway_cw_logs_policy" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cw-logs-policy"
  role = aws_iam_role.api_gateway_cw_logs_role.id

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



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = var.stack_name
    Project     = var.application_name
  }
}


# Placeholder - requires Lambda functions to be defined first


resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repository
 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token
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
         - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF

 tags = {
   Name        = "${var.application_name}-${var.stack_name}-amplify-app"
   Environment = var.stack_name
   Project     = var.application_name
 }


}


# Placeholder for Amplify Branch - needs actual S3 bucket


resource "aws_iam_role" "amplify_role" {
 name = "${var.application_name}-${var.stack_name}-amplify-role"

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

 tags = {
   Name        = "${var.application_name}-${var.stack_name}-amplify-role"
   Environment = var.stack_name
   Project     = var.application_name
 }
}

# Placeholder for Amplify Role Policy


# Placeholder for Lambda functions and related resources


output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}


