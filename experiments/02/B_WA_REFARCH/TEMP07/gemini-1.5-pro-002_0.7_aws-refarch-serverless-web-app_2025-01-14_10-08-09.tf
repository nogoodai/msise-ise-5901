terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider aws {
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

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "main"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_scopes                       = ["email", "phone", "openid"]

  callback_urls        = ["http://localhost:3000"] # Update with actual callback URLs
  logout_urls         = ["http://localhost:3000"] # Update with actual logout URLs

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = "prod"
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
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-lambda-role-${var.stack_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.application_name}-lambda-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# IAM Policy for Lambda function (DynamoDB access and CloudWatch Logs)
resource "aws_iam_policy" "lambda_policy" {
 name = "${var.application_name}-lambda-policy-${var.stack_name}"
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
          "dynamodb:Scan",
 "dynamodb:Query"
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
        Resource = "*"
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

 tags = {
 Name = "${var.application_name}-lambda-policy-${var.stack_name}"
 Environment = "prod"
 Project = var.application_name
 }
}

# Attach IAM policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
 role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_policy.arn
}

# Placeholder for Lambda functions (replace with actual function code)
# Example: Add Item function
resource "aws_lambda_function" "add_item_function" {
  function_name = "${var.application_name}-add-item-function-${var.stack_name}"
  handler       = "index.handler" # Replace with your handler
  runtime       = "nodejs16.x"
  role          = aws_iam_role.lambda_role.arn
 memory_size = 1024
 timeout = 60
  tracing_config {
 mode = "Active"
 }


 # Replace with your actual function code
  filename      = data.archive_file.add_item_zip.output_path
 source_code_hash = data.archive_file.add_item_zip.output_base64sha256


 tags = {
 Name = "${var.application_name}-add-item-function-${var.stack_name}"
 Environment = "prod"
 Project = var.application_name
 }
}

# Dummy zip file for demonstration purposes - replace with your actual function code
data "archive_file" "add_item_zip" {
 type        = "zip"
 source_dir  = "./dummy-lambda-function" # Replace with your function's directory
 output_path = "add_item_function.zip"
}


# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
 description = "API Gateway for ${var.application_name}"

 tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "prod"
 Project = var.application_name
 }
}

# API Gateway Authorizer (Cognito)
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "cognito_authorizer"
  type          = "COGNITO_USER_POOLS"
  rest_api_id  = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}

# API Gateway Resource (e.g., /item)
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

# API Gateway Method (e.g., POST /item)
resource "aws_api_gateway_method" "post_item_method" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_resource.id
 http_method = "POST"
 authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

# API Gateway Integration (Lambda)


resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.post_item_method.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype    = "Event"
  credentials             = aws_iam_role.lambda_role.arn # Assuming Lambda role has necessary permissions
  request_templates = {
 "application/json" = jsonencode({
 })
 }
 integration_uri = aws_lambda_function.add_item_function.invoke_arn
}



# API Gateway Stage (prod)
resource "aws_api_gateway_deployment" "prod_deployment" {

  rest_api_id = aws_api_gateway_rest_api.main.id


  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.item_resource.id,
      aws_api_gateway_method.post_item_method.http_method,
 aws_api_gateway_integration.post_item_integration.id,
    ]))
 }


 lifecycle {
 create_before_destroy = true
 }
}

resource "aws_api_gateway_stage" "prod_stage" {

  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"
 deployment_id = aws_api_gateway_deployment.prod_deployment.id


}

# Amplify App
resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo_url
  platform   = "WEB" # Set to WEB for a web application

  build_spec = jsonencode({
    version = 0.1,
    frontend = {
      phases = {
        preBuild  = "npm install",
 build     = "npm run build",
      }
 artifacts = {
        baseDirectory = "build", # Adjust if needed
 files       = ["**/*"],
      }
    }
  })

  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
 Environment = "prod"
    Project     = var.application_name
 }
}

# Amplify Branch (master)
resource "aws_amplify_branch" "master_branch" {
 app_id      = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true
}

# IAM Role for API Gateway logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.application_name}-api-gateway-cloudwatch-role-${var.stack_name}"

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

 tags = {
    Name        = "${var.application_name}-api-gateway-cloudwatch-role-${var.stack_name}"
    Environment = "prod"
 Project     = var.application_name
  }
}

# IAM Policy for API Gateway logging
resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
 name = "${var.application_name}-api-gateway-cloudwatch-policy-${var.stack_name}"
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

 tags = {
    Name = "${var.application_name}-api-gateway-cloudwatch-policy-${var.stack_name}"
 Environment = "prod"
    Project = var.application_name
 }
}


# Attach IAM policy to API Gateway role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_policy_attachment" {
  role       = aws_iam_role.api_gateway_cloudwatch_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}


# API Gateway Account Settings for CloudWatch logging
resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
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

output "api_gateway_url" {
 value = aws_api_gateway_deployment.prod_deployment.invoke_url
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "lambda_function_arn" {
 value = aws_lambda_function.add_item_function.arn
}
