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

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type    = string
  default = "your-github-repo" # Replace with your actual GitHub repository
}

variable "github_branch" {
  type    = string
  default = "main"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = true
    require_uppercase = true
    require_symbols   = false
    require_numbers   = false
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                        = aws_cognito_user_pool.main.id
  explicit_auth_flows                 = ["ADMIN_NO_SRP_AUTH"]
  generate_secret                     = false
  supported_identity_providers        = ["COGNITO"]
  callback_urls                       = ["http://localhost:3000/"] # Replace with your application's callback URL
  logout_urls                         = ["http://localhost:3000/"] # Replace with your application's logout URL
  allowed_oauth_flows                 = ["code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  prevent_user_existence_errors      = "ENABLED"
 refresh_token_validity               = 30


}



# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


# DynamoDB Table
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

}

# IAM Role for Lambda functions


resource "aws_iam_role" "lambda_role" {
  name = "lambda_role_${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Sid    = "",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# IAM Policy for Lambda to access DynamoDB and CloudWatch Logs
resource "aws_iam_policy" "lambda_policy" {
 name = "lambda_policy_${var.stack_name}"

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
            "dynamodb:Scan",

        ],
        Resource = aws_dynamodb_table.main.arn
    },
    {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
 },
 {
      Effect = "Allow",
        Action = [
            "xray:PutTraceSegments",
 "xray:PutTelemetryRecords"
        ],
        Resource = "*"
    }
  ]
 })

}


# Attach IAM policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_role_policy_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_policy.arn

}




# Placeholder for Lambda functions - replace with your actual Lambda function code
resource "aws_lambda_function" "add_item" {
  function_name = "add_item_${var.stack_name}"
  handler       = "index.handler" # Replace with your handler
 runtime     = "nodejs12.x"
  memory_size   = 1024
  timeout       = 60
  role          = aws_iam_role.lambda_role.arn
 tracing_config {
    mode = "Active"
 }

 # Replace with your Lambda function code
  source_code_hash = filebase64sha256("./mock-lambda.zip") # Replace with your function's zip file
}


resource "null_resource" "lambda_zip" {
  provisioner "local-exec" {
    command = "zip -j mock-lambda.zip mock-lambda.js"
  }
}



# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-${var.stack_name}-api"
  description = "API Gateway for ${var.application_name}"
}



resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_resource" "item_id_resource" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 parent_id   = aws_api_gateway_resource.item_resource.id
  path_part   = "{id}"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id


}


resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id   = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"

 integration_uri = aws_lambda_function.add_item.invoke_arn
}


resource "aws_api_gateway_deployment" "deployment" {
 rest_api_id = aws_api_gateway_rest_api.main.id

 triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.main.body))
 }

 depends_on = [
   aws_api_gateway_integration.post_item_integration
 ]

}



resource "aws_api_gateway_stage" "prod" {
 deployment_id = aws_api_gateway_deployment.deployment.id
 rest_api_id   = aws_api_gateway_rest_api.main.id
 stage_name    = "prod"
}




resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito_authorizer_${var.stack_name}"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
  type          = "COGNITO_USER_POOLS"
}

# Amplify App (Placeholder - replace with your actual GitHub repository details)

resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}-amplify"
 repository = var.github_repo
  access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with a GitHub Personal Access Token
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
          - aws s3 sync --delete s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF
}


resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-amplify-bucket"

}




resource "aws_amplify_branch" "main" {
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

output "cognito_user_pool_domain" {
 value = aws_cognito_user_pool_domain.main.domain
}

output "dynamodb_table_name" {
 value = aws_dynamodb_table.main.name
}

output "api_gateway_url" {
 value = aws_api_gateway_deployment.deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


