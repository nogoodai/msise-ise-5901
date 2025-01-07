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
  default = "serverless-todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type    = string
  default = "your-github-repo" # Replace with your GitHub repository
}

variable "github_branch" {
  type    = string
  default = "master"
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
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "${var.application_name}-user-pool-client-${var.stack_name}"

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Placeholder URL, update accordingly
  logout_urls = ["http://localhost:3000/"] # Placeholder URL, update accordingly

  supported_identity_providers = ["COGNITO"]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
  read_capacity = 5
  write_capacity = 5

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

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
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
        Principal = {
 Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}


# IAM Policy for Lambda functions (DynamoDB and CloudWatch)
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_policy_${var.stack_name}"
 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ],
        Effect   = "Allow",
 Resource = aws_dynamodb_table.main.arn
      },
 {
        Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
          "logs:PutLogEvents",
 "xray:PutTraceSegments",
 "xray:PutTelemetryRecords",
        ],
        Effect = "Allow",
        Resource = "*"
      },

    ]
  })

}

# Attach IAM Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# Lambda Functions (Placeholder - replace with your actual Lambda function code)
resource "aws_lambda_function" "add_item" {
  function_name = "add_item_${var.stack_name}"
  filename      = "add_item.zip" # Replace with your Lambda function zip file
  source_code_hash = filebase64sha256("add_item.zip") # Replace with your Lambda function zip file
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler" # Replace with your handler
  runtime       = "nodejs12.x" # Replace with the runtime you are using
 memory_size = 1024
  timeout       = 60

  tracing_config {
    mode = "Active"
  }
}

# Repeat the above Lambda function resource for other functions:
# get_item, get_all_items, update_item, complete_item, delete_item

# API Gateway Rest API


resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
}


resource "aws_api_gateway_authorizer" "cognito_authorizer" {
 name                   = "cognito_authorizer"
  rest_api_id            = aws_api_gateway_rest_api.main.id
  provider_arns          = [aws_cognito_user_pool.main.arn]
  type                    = "COGNITO_USER_POOLS"
  identity_source        = "method.request.header.Authorization"
}




# API Gateway Resources and Methods (Example for Add Item)
resource "aws_api_gateway_resource" "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id  = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

}

# API Gateway Integration (Example for Add Item)
resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id  = aws_api_gateway_resource.item_resource.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
 type                    = "aws_proxy"
  integration_subtype = "Event"
  credentials =  aws_iam_role.lambda_role.arn
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })

  }
  integration_uri = aws_lambda_function.add_item.invoke_arn
}



# IAM Role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name = "api_gateway_role_${var.stack_name}"
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


# IAM Policy for API Gateway (CloudWatch Logs)
resource "aws_iam_policy" "api_gateway_policy" {

  name = "api_gateway_policy_${var.stack_name}"

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


# Attach IAM Policy to API Gateway Role
resource "aws_iam_role_policy_attachment" "api_gateway_policy_attachment" {
 role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_policy.arn
}



# API Gateway Deployment
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

 depends_on = [
    aws_api_gateway_integration.post_item_integration, # Include all integrations here
  ]
}


# API Gateway Stage
resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"
}



# Amplify App
resource "aws_amplify_app" "main" {

  name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with a valid access token

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
 artifacts:
    baseDirectory: /
    files:
      - '**/*'

EOF
}

# Amplify Branch
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
 enable_auto_build = true
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
  value = aws_api_gateway_deployment.deployment.invoke_url
}


output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}


