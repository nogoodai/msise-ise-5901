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
  default     = "us-west-2"
}

variable "stack_name" {
  type        = string
  description = "The name of the stack."
  default     = "todo-app"
}

variable "application_name" {
  type        = string
  description = "The name of the application."
  default     = "todo-app"
}

variable "github_repo_url" {
  type        = string
  description = "The URL of the GitHub repository."
  default     = "https://github.com/your-username/your-repo"
}

variable "github_branch" {
  type        = string
  description = "The branch of the GitHub repository."
  default     = "main"
}

variable "allowed_origins" {
  type        = list(string)
  description = "List of allowed origins for CORS."
  default     = ["http://localhost:3000"]
}

variable "callback_urls" {
  type        = list(string)
  description = "List of callback URLs for Cognito User Pool Client."
  default     = ["http://localhost:3000/"]
}

variable "logout_urls" {
  type        = list(string)
  description = "List of logout URLs for Cognito User Pool Client."
  default     = ["http://localhost:3000/"]
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
 mfa_configuration = "OFF" # Explicitly set MFA to OFF

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = "dev"
    Project     = var.application_name
  }
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
  callback_urls                       = var.callback_urls
  logout_urls                         = var.logout_urls
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
 point_in_time_recovery {
    enabled = false # Explicitly disable point-in-time recovery
 }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "dev"
    Project     = var.application_name
  }
}


resource "aws_apigatewayv2_api" "main" {
  name          = "${var.application_name}-${var.stack_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["*"]
    allow_methods = ["*"]
    allow_origins = var.allowed_origins
  }

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-api"
    Environment = "dev"
    Project     = var.application_name
  }
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name         = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId = "$context.requestId",
      ip        = "$context.identity.sourceIp",
      requestTime = "$context.requestTime",
      httpMethod = "$context.httpMethod",
      routeKey = "$context.routeKey",
 status = "$context.status",
      protocol = "$context.protocol",
      responseLength = "$context.responseLength"
    })
  }


  default_route_settings {
    data_trace_enabled = true
    detailed_metrics_enabled = true
 logging_level = "INFO"
  }

  tags = {
    Name        = "prod"
    Environment = "dev"
    Project     = var.application_name
  }

}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/apigateway/${aws_apigatewayv2_api.main.name}/access_logs"
  retention_in_days = 7
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
 tags = {
    Name = "${var.application_name}-${var.stack_name}-lambda-role"
 Environment = "dev"
 Project = var.application_name
  }
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
 "dynamodb:Scan"
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
        Effect   = "Allow",
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

  tags = {
    Name = "${var.application_name}-${var.stack_name}-lambda-policy"
    Environment = "dev"
    Project = var.application_name
  }
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
 tags = {
 Name = "${var.application_name}-${var.stack_name}-example-function"
    Environment = "dev"
    Project = var.application_name
 }
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

}


resource "aws_amplify_branch" "main" {
 app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
 enable_auto_build = true
}



resource "aws_s3_bucket" "main" {
 bucket = "${var.application_name}-${var.stack_name}-s3-bucket"

  versioning {
 enabled = true
 }
 logging {
 target_bucket = "${var.application_name}-${var.stack_name}-s3-bucket-logs"
 target_prefix = "log/"
 }
 server_side_encryption_configuration {
 rule {
 apply_server_side_encryption_by_default {
 sse_algorithm     = "AES256"
 }
 }
 }

  tags = {
 Name = "${var.application_name}-${var.stack_name}-s3-bucket"
    Environment = "dev"
 Project = var.application_name
 }
}

resource "aws_s3_bucket" "log_bucket" {
 bucket = "${var.application_name}-${var.stack_name}-s3-bucket-logs"
 acl    = "log-delivery-write"
 force_destroy = true

 server_side_encryption_configuration {
 rule {
 apply_server_side_encryption_by_default {
          sse_algorithm = "AES256"
 }
 }
 }
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

 tags = {
    Name = "${var.application_name}-${var.stack_name}-amplify-role"
    Environment = "dev"
    Project = var.application_name
  }
}

resource "aws_iam_policy" "amplify_policy" {
  name = "${var.application_name}-${var.stack_name}-amplify-policy"
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
 Effect = "Allow",
        Action = [
          "s3:*"
        ],
        Resource = [
 aws_s3_bucket.main.arn,
          "${aws_s3_bucket.main.arn}/*"
        ]
      }
    ]
  })
 tags = {
    Name = "${var.application_name}-${var.stack_name}-amplify-policy"
    Environment = "dev"
    Project = var.application_name
  }
}

resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
 role       = aws_iam_role.amplify_role.name
 policy_arn = aws_iam_policy.amplify_policy.arn
}


output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_api.main.api_endpoint
  description = "The URL of the API Gateway."
}

output "amplify_app_id" {
  value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}
