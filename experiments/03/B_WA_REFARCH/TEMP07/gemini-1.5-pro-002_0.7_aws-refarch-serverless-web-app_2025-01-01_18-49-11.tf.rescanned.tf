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

  default = "todo-app"
}

variable "github_repo" {
  type        = string
  description = "The URL of the GitHub repository."
}

variable "github_access_token" {
  type        = string
  description = "GitHub personal access token."
  sensitive   = true
}

variable "api_key" {
  type        = string
  description = "API Key for API Gateway."
  sensitive   = true
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers = true
    require_symbols = true
  }

  username_attributes = ["email"]

  verification_message_template {
    default_email_options {
      delivery_method = "EMAIL"
    }
  }

  auto_verified_attributes = ["email"]
 mfa_configuration = "OFF"

  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                        = aws_cognito_user_pool.main.id
  generate_secret                     = false
  allowed_oauth_flows                 = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Replace with your callback URL
  allowed_oauth_flows_user_pool_client = true
  prevent_user_existence_errors      = "ENABLED"


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
  billing_mode   = "PAY_PER_REQUEST"
 server_side_encryption {
    enabled = true
  }

 attribute {
    name = "cognito-username"
    type = "S"
  }
  hash_key = "cognito-username"

  attribute {
    name = "id"
    type = "S"
  }
 range_key = "id"

 point_in_time_recovery {
 enabled = true
 }


  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}




# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role_${var.stack_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    Name        = "lambda_role_${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# IAM Policy for Lambda to access DynamoDB
resource "aws_iam_policy" "lambda_dynamodb_policy" {
 name = "lambda_dynamodb_policy_${var.stack_name}"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowDynamoDBAccess",
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:BatchGetItem",
 "dynamodb:BatchWriteItem",
 "dynamodb:ConditionCheckItem",
 "dynamodb:DeleteItem",
 "dynamodb:GetItem",
 "dynamodb:PutItem",
 "dynamodb:Query",
 "dynamodb:Scan",
 "dynamodb:UpdateItem"

        ],
        "Resource" : aws_dynamodb_table.main.arn
      },
            {
        "Sid" : "AllowXray",
        "Effect" : "Allow",
        "Action" : [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        "Resource": "*"

      },
      {
        "Sid" : "AllowLogs",
        "Effect" : "Allow",
        "Action" : [
           "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
        ],
        "Resource" : "*"

      }
    ]
  })
  

  tags = {
    Name        = "lambda_dynamodb_policy_${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# Attach the policy to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}



# Placeholder for Lambda functions - replace with your actual Lambda function code
resource "aws_lambda_function" "lambda_functions" {
  for_each = {
    "add_item"    = { handler = "index.handler", filename = "add_item.zip", description = "Add Item Lambda Function" } # Replace with your Lambda zip file
    "get_item" = { handler = "index.handler", filename = "get_item.zip", description = "Get Item Lambda Function" } # Replace with your Lambda zip file
        "get_all_items" = { handler = "index.handler", filename = "get_all_items.zip", description = "Get All Items Lambda Function" } # Replace with your Lambda zip file
        "update_item" = { handler = "index.handler", filename = "update_item.zip", description = "Update Item Lambda Function" } # Replace with your Lambda zip file

                "complete_item" = { handler = "index.handler", filename = "complete_item.zip", description = "Complete Item Lambda Function" } # Replace with your Lambda zip file

        "delete_item" = { handler = "index.handler", filename = "delete_item.zip", description = "Delete Item Lambda Function" } # Replace with your Lambda zip file

  }

 filename   = each.value.filename
  function_name = "${var.application_name}-${each.key}-${var.stack_name}"
  handler        = each.value.handler
  role           = aws_iam_role.lambda_role.arn
  runtime = "nodejs16.x" # Replace with your desired runtime
  memory_size = 1024
  timeout = 60
  tracing_config {
    mode = "Active"
  }

 source_code_hash = filebase64sha256(each.value.filename)


  tags = {
    Name        = "${var.application_name}-${each.key}-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}




# API Gateway - Create REST API
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


# API Gateway - Create Resource
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



# API Gateway - Create Method - POST /item
resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
 api_key_required = true


}

# API Gateway - Create Integration - POST /item
resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"
  credentials = aws_iam_role.lambda_role.arn

  integration_method = "POST"
  passthrough_behavior = "WHEN_NO_MATCH"


  request_template = <<EOF
{
  "cognito-username": "$context.authorizer.claims.username",
  "body": $input.json('$')
}
EOF

  integration_uri = aws_lambda_function.lambda_functions["add_item"].invoke_arn
}


# API Gateway - Create Method - GET /item
resource "aws_api_gateway_method" "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
 api_key_required = true

}

# API Gateway - Create Integration - GET /item
resource "aws_api_gateway_integration" "get_all_items_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.get_all_items.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"

  integration_method = "POST"
  passthrough_behavior = "WHEN_NO_MATCH"
 credentials = aws_iam_role.lambda_role.arn

 request_template = <<EOF
{
  "cognito-username": "$context.authorizer.claims.username"
}
EOF
  integration_uri = aws_lambda_function.lambda_functions["get_all_items"].invoke_arn
}

# API Gateway - Create Method - GET /item/{id}
resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_id_resource.id

  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
 api_key_required = true


}

# API Gateway - Create Integration - GET /item/{id}
resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
    resource_id = aws_api_gateway_resource.item_id_resource.id

  http_method             = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"
  integration_method = "POST"
  passthrough_behavior = "WHEN_NO_MATCH"
 credentials = aws_iam_role.lambda_role.arn

 request_template = <<EOF
{
  "cognito-username": "$context.authorizer.claims.username",
    "id": "$input.params('id')"
}
EOF
  integration_uri = aws_lambda_function.lambda_functions["get_item"].invoke_arn
}


# API Gateway - Create Method - PUT /item/{id}
resource "aws_api_gateway_method" "update_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_id_resource.id

  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
 api_key_required = true


}

# API Gateway - Create Integration - PUT /item/{id}
resource "aws_api_gateway_integration" "update_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
    resource_id = aws_api_gateway_resource.item_id_resource.id

  http_method             = aws_api_gateway_method.update_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"
  integration_method = "POST"
  passthrough_behavior = "WHEN_NO_MATCH"
 credentials = aws_iam_role.lambda_role.arn

 request_template = <<EOF
{
  "cognito-username": "$context.authorizer.claims.username",
    "id": "$input.params('id')",
    "body": $input.json('$')

}
EOF
  integration_uri = aws_lambda_function.lambda_functions["update_item"].invoke_arn
}


# API Gateway - Create Method - DELETE /item/{id}
resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_id_resource.id

  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
 api_key_required = true


}

# API Gateway - Create Integration - DELETE /item/{id}
resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
    resource_id = aws_api_gateway_resource.item_id_resource.id

  http_method             = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
    integration_subtype = "Event"

  integration_method = "POST"
  passthrough_behavior = "WHEN_NO_MATCH"
 credentials = aws_iam_role.lambda_role.arn

 request_template = <<EOF
{
  "cognito-username": "$context.authorizer.claims.username",
    "id": "$input.params('id')"
}
EOF
  integration_uri = aws_lambda_function.lambda_functions["delete_item"].invoke_arn
}



# API Gateway - Cognito Authorizer
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "${var.application_name}-cognito-authorizer-${var.stack_name}"
  type          = "COGNITO_USER_POOLS"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  provider_arns = [aws_cognito_user_pool.main.arn]
}



# API Gateway - Deployment
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_integration.post_item_integration,
    aws_api_gateway_integration.get_all_items_integration,
        aws_api_gateway_integration.get_item_integration,
                aws_api_gateway_integration.update_item_integration,
                aws_api_gateway_integration.delete_item_integration
  ]
 rest_api_id = aws_api_gateway_rest_api.main.id

  stage_name = "prod"

}

resource "aws_cloudwatch_log_group" "api_gw" {
 name = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}-prod"
 retention_in_days = 30

}



# API Gateway - Stage
resource "aws_api_gateway_stage" "prod" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id
 xray_tracing_enabled = true
 access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      "requestId": "$context.requestId",
      "ip": "$context.identity.sourceIp",
      "caller": "$context.identity.caller",
      "user": "$context.identity.user",
      "requestTime": "$context.requestTime",
      "httpMethod": "$context.httpMethod",
      "resourcePath": "$context.resourcePath",
      "status": "$context.status",
      "protocol": "$context.protocol",
      "responseLength": "$context.responseLength"
    })
  }

  tags = {
    Name        = "${var.application_name}-api-stage-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# API Gateway - Usage Plan
resource "aws_api_gateway_usage_plan" "main" {
  name         = "${var.application_name}-usage-plan-${var.stack_name}"
 description = "Usage plan for ${var.application_name}"

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

resource "aws_api_gateway_api_key" "main" {
  name = "${var.application_name}-api-key-${var.stack_name}"
  value = var.api_key

}

resource "aws_api_gateway_usage_plan_key" "main" {
  key_id        = aws_api_gateway_api_key.main.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.main.id
}



resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repo
 access_token = var.github_access_token
 build_spec = <<EOF
version: 0.1
frontend:
 phases:
  install:
   commands:
    - npm install
  preBuild:
   commands:
    - npm run build
  build:
   commands:
    - npm run export
 artifacts:
  baseDirectory: /out
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
  app_id      = aws_amplify_app.main.id
  branch_name = "master"
  enable_auto_build = true
}


# IAM Role for API Gateway to write logs to CloudWatch
resource "aws_iam_role" "api_gateway_role" {
  name = "api_gateway_role_${var.stack_name}"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Sid": "",
   "Effect": "Allow",
   "Principal": {
    "Service": "apigateway.amazonaws.com"
   },
   "Action": "sts:AssumeRole"
  }
 ]
}
EOF

 tags = {
    Name = "api_gateway_role_${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
 }
}


# IAM Policy for API Gateway to write logs to CloudWatch
resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
 name = "api_gateway_cloudwatch_policy_${var.stack_name}"

 policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
 {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "*"
      }
    ]
 })
  


 tags = {
    Name = "api_gateway_cloudwatch_policy_${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
 }


}

# Attach the policy to the API Gateway role
resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn
}


# API Gateway Account
resource "aws_api_gateway_account" "main" {

 cloudwatch_role_arn = aws_iam_role.api_gateway_role.arn
}


# Outputs
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "The ID of the Cognito User Pool."
}

output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.main.id
  description = "The ID of the Cognito User Pool Client."
}

output "cognito_user_pool_domain" {
 value       = aws_cognito_user_pool_domain.main.domain
  description = "The domain of the Cognito User Pool."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.main.name
  description = "The name of the DynamoDB table."
}

output "api_gateway_url" {
 value       = aws_api_gateway_deployment.main.invoke_url
  description = "The URL of the API Gateway."
}

output "amplify_app_id" {
 value       = aws_amplify_app.main.id
  description = "The ID of the Amplify app."
}

output "amplify_default_domain" {
 value       = aws_amplify_app.main.default_domain
  description = "The default domain of the Amplify app."
}
output "api_gateway_api_key" {
  value = aws_api_gateway_api_key.main.value
 sensitive = true
  description = "The API key for the API Gateway."
}

