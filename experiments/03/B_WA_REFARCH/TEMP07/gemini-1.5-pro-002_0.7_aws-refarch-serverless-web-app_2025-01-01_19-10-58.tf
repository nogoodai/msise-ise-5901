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

variable "github_repo_url" {
  type    = string
  default = "https://github.com/your-username/your-repo"
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
  username_attributes      = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name               = "${var.application_name}-${var.stack_name}-client"
  user_pool_id       = aws_cognito_user_pool.main.id
  generate_secret    = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Replace with your callback URL
  logout_urls                         = ["http://localhost:3000/"] # Replace with your logout URL

  supported_identity_providers = ["COGNITO"]
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
}


resource "aws_apigatewayv2_api" "main" {
 name          = "${var.application_name}-${var.stack_name}-api"
 protocol_type = "HTTP"

 cors_configuration {
   allow_headers = ["*"]
   allow_methods = ["*"]
   allow_origins = ["*"] # Replace with your allowed origins
 }
}


resource "aws_apigatewayv2_stage" "prod" {
 api_id      = aws_apigatewayv2_api.main.id
 name         = "prod"
 auto_deploy = true
}

resource "aws_apigatewayv2_usage_plan" "main" {
 name = "${var.application_name}-${var.stack_name}-usage-plan"

 throttle_settings {
   burst_limit = 100
   rate_limit  = 50
 }

 quota_settings {
   limit  = 5000
   offset = 0
   period = "DAY"
 }
}


resource "aws_iam_role" "lambda_role" {
 name = "${var.application_name}-${var.stack_name}-lambda-role"

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

resource "aws_iam_policy" "lambda_policy" {

 name = "${var.application_name}-${var.stack_name}-lambda-policy"
 policy = jsonencode({
   Version = "2012-10-17",
   Statement = [
     {
       Action = [
         "logs:CreateLogGroup",
         "logs:CreateLogStream",
         "logs:PutLogEvents",
       ],
       Effect   = "Allow",
       Resource = "arn:aws:logs:*:*:*"
     },
     {
       Action = [
         "dynamodb:GetItem",
         "dynamodb:PutItem",
         "dynamodb:UpdateItem",
         "dynamodb:DeleteItem",
         "dynamodb:Scan",

       ],
       Effect   = "Allow",
       Resource = aws_dynamodb_table.main.arn
     },
     {
       Action = [
         "xray:PutTraceSegments",
         "xray:PutTelemetryRecords",
         "xray:GetSamplingRules",
         "xray:GetSamplingTargets",
         "xray:GetSamplingStatisticSummaries"
       ],
       Effect = "Allow",
       Resource = "*"

     },
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
   ]
 })
}


resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_policy.arn
}


# Placeholder for Lambda functions - replace with actual function code
resource "aws_lambda_function" "example_lambda" {
  function_name = "${var.application_name}-${var.stack_name}-example-function"
  handler       = "index.handler" # Replace with your handler
  role          = aws_iam_role.lambda_role.arn
  runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60
  tracing_config {
    mode = "Active"
  }

 # Replace with actual function code
  filename         = "lambda_function.zip" # Replace with path to your zip file
 source_code_hash = filebase64sha256("lambda_function.zip")

}



resource "aws_amplify_app" "main" {
 name       = "${var.application_name}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url

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
     postBuild:
        commands:
          - aws s3 sync build/ s3://${aws_s3_bucket.main.bucket}
 artifacts:
   baseDirectory: /
   files:
     - '**/*'
EOF
  # platform = "WEB"
}


resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true
}



resource "aws_s3_bucket" "main" {
  bucket = "${var.application_name}-${var.stack_name}-s3-bucket"
}


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
     },
   ]
 })
}


resource "aws_iam_policy" "amplify_policy" {
 name = "${var.application_name}-${var.stack_name}-amplify-policy"
 policy = jsonencode({
   Version = "2012-10-17",
   Statement = [
     {
       Effect = "Allow",
       Action = "*",
       Resource = "*"
     }
   ]
 })
}


resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
 role       = aws_iam_role.amplify_role.name
 policy_arn = aws_iam_policy.amplify_policy.arn
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
 value = aws_apigatewayv2_api.main.api_endpoint
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


