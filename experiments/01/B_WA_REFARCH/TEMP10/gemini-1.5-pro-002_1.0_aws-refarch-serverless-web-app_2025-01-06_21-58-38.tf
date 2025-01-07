terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider aws {
  region = var.aws_region
}


variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "todo-app-stack"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type    = string
  default = "your-github-repo"
}

variable "github_branch" {
  type    = string
  default = "master"
}


# Cognito User Pool
resource aws_cognito_user_pool "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 6
    require_lowercase                = true
    require_numbers                  = false
    require_symbols                  = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }
  tags = {
    Name        = "${var.application_name}-user-pool-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Client
resource aws_cognito_user_pool_client "main" {
  name                                 = "${var.application_name}-user-pool-client-${var.stack_name}"
  user_pool_id                        = aws_cognito_user_pool.main.id
  generate_secret                     = false
  allowed_oauth_flows                 = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Placeholder URL, update with your actual callback URL
  logout_urls                         = ["http://localhost:3000/"] # Placeholder URL, update with your actual logout URL
  supported_identity_providers        = ["COGNITO"]

  tags = {
    Name        = "${var.application_name}-user-pool-client-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Cognito User Pool Domain
resource aws_cognito_user_pool_domain "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
  tags = {
    Name        = "${var.application_name}-user-pool-domain-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}

# DynamoDB Table
resource aws_dynamodb_table "todo_table" {
  name         = "todo-table-${var.stack_name}"
  billing_mode = "PROVISIONED"
  read_capacity = 5
  write_capacity = 5
  hash_key      = "cognito-username"
  range_key     = "id"
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


# IAM Role for API Gateway Logging
resource aws_iam_role "api_gateway_cloudwatch_role" {
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

# IAM Policy for API Gateway Logging
resource aws_iam_role_policy "api_gateway_cloudwatch_policy" {
  name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id


  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })

}

#  API Gateway
resource aws_api_gateway_rest_api "main" {
 name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"

 tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}

# API Gateway Deployment

resource aws_api_gateway_deployment "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"


  depends_on = [
    aws_api_gateway_integration.add_item,
 aws_api_gateway_integration.get_item,
    aws_api_gateway_integration.get_all_items,
    aws_api_gateway_integration.update_item,
    aws_api_gateway_integration.complete_item,
    aws_api_gateway_integration.delete_item

  ]

}





# Lambda Functions (Placeholders - replace with your actual Lambda function code)

resource aws_lambda_function "add_item" {
 filename      = "add_item.zip" # Replace with your function code
  function_name = "add-item-${var.stack_name}"
 handler       = "index.handler"
  runtime = "nodejs12.x"
  memory_size = 1024
 timeout = 60
 role          = aws_iam_role.lambda_exec_role.arn
 source_code_hash = filebase64sha256("add_item.zip")


  tracing_config {
    mode = "Active"
  }


  tags = {
    Name        = "add-item-lambda-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }

}


resource aws_lambda_function "get_item" {
 filename      = "get_item.zip" # Replace with your function code
  function_name = "get-item-${var.stack_name}"
 handler       = "index.handler"
  runtime = "nodejs12.x"
  memory_size = 1024
 timeout = 60
 role          = aws_iam_role.lambda_exec_role.arn
 source_code_hash = filebase64sha256("get_item.zip")


  tracing_config {
    mode = "Active"
  }


  tags = {
    Name        = "get-item-lambda-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource aws_lambda_function "get_all_items" {

 filename      = "get_all_items.zip" # Replace with your function code
  function_name = "get-all-items-${var.stack_name}"
 handler       = "index.handler"
  runtime = "nodejs12.x"
  memory_size = 1024
 timeout = 60
 role          = aws_iam_role.lambda_exec_role.arn
 source_code_hash = filebase64sha256("get_all_items.zip")



  tracing_config {
    mode = "Active"
  }


  tags = {
    Name        = "get-all-items-lambda-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource aws_lambda_function "update_item" {
 filename      = "update_item.zip" # Replace with your function code
  function_name = "update-item-${var.stack_name}"
 handler       = "index.handler"
  runtime = "nodejs12.x"
  memory_size = 1024
 timeout = 60
 role          = aws_iam_role.lambda_exec_role.arn
 source_code_hash = filebase64sha256("update_item.zip")


  tracing_config {
    mode = "Active"
  }


  tags = {
    Name        = "update-item-lambda-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource aws_lambda_function "complete_item" {
 filename      = "complete_item.zip" # Replace with your function code
  function_name = "complete-item-${var.stack_name}"
 handler       = "index.handler"
  runtime = "nodejs12.x"
  memory_size = 1024
 timeout = 60
 role          = aws_iam_role.lambda_exec_role.arn
 source_code_hash = filebase64sha256("complete_item.zip")


  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "complete-item-lambda-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource aws_lambda_function "delete_item" {

 filename      = "delete_item.zip" # Replace with your function code
  function_name = "delete-item-${var.stack_name}"
 handler       = "index.handler"
  runtime = "nodejs12.x"
  memory_size = 1024
 timeout = 60
 role          = aws_iam_role.lambda_exec_role.arn
 source_code_hash = filebase64sha256("delete_item.zip")


  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "delete-item-lambda-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


# IAM Role for Lambda Execution
resource aws_iam_role "lambda_exec_role" {
  name = "lambda-exec-role-${var.stack_name}"

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
    Name        = "lambda-exec-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}



# IAM Policy for Lambda to access DynamoDB and CloudWatch
resource aws_iam_policy "lambda_dynamodb_cloudwatch_policy" {

  name        = "lambda-dynamodb-cloudwatch-policy-${var.stack_name}"



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
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem"
        ],

        Resource = aws_dynamodb_table.todo_table.arn

      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
                Resource = "*"
      },
      {
        Action = [
          "cloudwatch:PutMetricData"
        ],
        Effect    = "Allow",
        Resource = "*"
      }

    ]
  })
}

# Attach the policy to the Lambda role
resource aws_iam_role_policy_attachment "lambda_dynamodb_cloudwatch_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_cloudwatch_policy.arn
}

# API Gateway Resources and Methods

resource aws_api_gateway_resource "item_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource aws_api_gateway_resource "item_id_resource" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.item_resource.id
  path_part   = "{id}"
}



resource aws_api_gateway_method "add_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id


}


resource aws_api_gateway_method "get_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_id_resource.id
  http_method = "GET"
    authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

}




resource aws_api_gateway_method "get_all_items" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "GET"
    authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

}



resource aws_api_gateway_method "update_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_id_resource.id
  http_method = "PUT"
    authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

}




resource aws_api_gateway_method "complete_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_id_resource.id
  http_method = "POST"
    authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

}




resource aws_api_gateway_method "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_id_resource.id
  http_method = "DELETE"
    authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

}
# API Gateway Integrations
resource aws_api_gateway_integration "add_item" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.add_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  integration_subtype    = "EventLambda-Invoke"
  credentials             = aws_iam_role.lambda_exec_role.arn
  request_templates = {
    "application/json" = <<EOF
{
  "cognito-username": "$header.Authorization",
  "body" : $input.json('$')
}
EOF
  }
 integration_uri = aws_lambda_function.add_item.invoke_arn

}

resource aws_api_gateway_integration "get_item" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
  http_method             = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  integration_subtype    = "EventLambda-Invoke"
  credentials             = aws_iam_role.lambda_exec_role.arn
 integration_uri = aws_lambda_function.get_item.invoke_arn

}


resource aws_api_gateway_integration "get_all_items" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.get_all_items.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  integration_subtype    = "EventLambda-Invoke"
  credentials             = aws_iam_role.lambda_exec_role.arn
  request_templates = {
    "application/json" = <<EOF
{
  "cognito-username": "$header.Authorization",
  "body" : $input.json('$')
}
EOF
  }
 integration_uri = aws_lambda_function.get_all_items.invoke_arn
}




resource aws_api_gateway_integration "update_item" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
  http_method             = aws_api_gateway_method.update_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  integration_subtype    = "EventLambda-Invoke"
  credentials             = aws_iam_role.lambda_exec_role.arn
 integration_uri = aws_lambda_function.update_item.invoke_arn
}




resource aws_api_gateway_integration "complete_item" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
  http_method             = aws_api_gateway_method.complete_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  integration_subtype    = "EventLambda-Invoke"
  credentials             = aws_iam_role.lambda_exec_role.arn
 integration_uri = aws_lambda_function.complete_item.invoke_arn
}




resource aws_api_gateway_integration "delete_item" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_id_resource.id
  http_method             = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  integration_subtype    = "EventLambda-Invoke"
  credentials             = aws_iam_role.lambda_exec_role.arn
 integration_uri = aws_lambda_function.delete_item.invoke_arn
}

# API Gateway Authorizer

resource aws_api_gateway_authorizer "cognito_authorizer" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  provider_arns  = [aws_cognito_user_pool.main.arn]
}

# API Gateway Stage

resource aws_api_gateway_stage "prod" {
  stage_name        = "prod"
  rest_api_id = aws_api_gateway_rest_api.main.id
  deployment_id = aws_api_gateway_deployment.main.id

 access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({
      requestId = "$context.requestId"
      ip       = "$context.identity.sourceIp"
      user     = "$context.identity.user"
      caller   = "$context.authorizer.principalId"
      userArn  = "$context.authorizer.arn"
      requestTime = "$context.requestTime"
      httpMethod = "$context.httpMethod"
      resourcePath = "$context.resourcePath"
      status = "$context.status"
      protocol = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      integrationLatency = "$context.integrationLatency"
      integrationStatus = "$context.integrationStatus"
    })
  }

}

# API Gateway Usage Plan

resource aws_api_gateway_usage_plan "my_usage_plan" {
 name         = "my_usage_plan-${var.stack_name}"
  description = "Usage plan for ${var.application_name} API"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }


 throttle {
    burst_limit = 100
    rate_limit  = 50
  }

 quota {
    limit = 5000
 period = "DAY"
  }


}

# CloudWatch Log Group for API Gateway


resource aws_cloudwatch_log_group "api_gw" {
  name = "/aws/apigateway/${var.application_name}-api-${var.stack_name}"
  retention_in_days = 30

  tags = {
    Name        = "api_gw_logs-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

# Amplify App

resource aws_amplify_app "main" {
  name       = "${var.application_name}-amplify-${var.stack_name}"
  repository = var.github_repo

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
  artifacts:
    baseDirectory: /
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF

  tags = {
    Name        = "${var.application_name}-amplify-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}

resource aws_amplify_branch "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true

}


# IAM role for Amplify


resource aws_iam_role "amplify_role" {
  name = "amplify-role-${var.stack_name}"


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
    Name        = "amplify-role-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}


resource aws_iam_role_policy_attachment "amplify_policy_attachment" {
  role       = aws_iam_role.amplify_role.name
 policy_arn = "arn:aws:iam::aws:policy/AmplifyFullAccess"
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
  value = aws_dynamodb_table.todo_table.name
}

output "api_gateway_url" {
  value = aws_api_gateway_deployment.main.invoke_url
}

output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}

