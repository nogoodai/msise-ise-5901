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

variable "environment" {
  type    = string
  default = "dev"
}

variable "project" {
  type    = string
  default = "todo-app"
}

variable "stack_name" {
  type    = string
  default = "todo-app-stack"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project}-user-pool-${var.environment}"
  email_verification_message = "Your verification code is {####}"
  email_verification_subject = "Verify Your Email"

  password_policy {
    minimum_length                   = 6
    require_lowercase                = true
    require_numbers                  = false
    require_symbols                  = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  schema {
    attribute_data_type      = "String"
    developer_only           = false
    mutable                 = true
    name                    = "email"
    required                = true
    string_attribute_constraints {
      max_length = "256"
      min_length = "0"
    }

  }

  username_attributes      = ["email"]
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_message        = "Your verification code is {####}"
    email_subject        = "Verify Your Email"
    sms_message          = "Your verification code is {####}"
  }
 auto_verified_attributes = ["email"]
}


resource "aws_cognito_user_pool_client" "main" {
  name                               = "${var.project}-user-pool-client-${var.environment}"
  user_pool_id                      = aws_cognito_user_pool.main.id
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                = ["code", "implicit"]
  allowed_oauth_scopes               = ["email", "phone", "openid"]
  callback_urls                     = ["http://localhost:3000/"] # Replace with your callback URL
  generate_secret                   = false
  prevent_user_existence_errors    = "ENABLED"
  refresh_token_validity             = 30
  supported_identity_providers       = ["COGNITO"]

}


resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
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
 tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }

}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Sid    = ""
      },
    ]
  })

 tags = {
    Name        = "api-gateway-cloudwatch-role"
    Environment = var.environment
    Project     = var.project
  }
}



resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.environment}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id

  policy = jsonencode({
 Version = "2012-10-17"
 Statement = [
 {
        Effect = "Allow"
 Action = [
 "logs:CreateLogGroup",
 "logs:CreateLogStream",
 "logs:PutLogEvents"
 ]
 Resource = "*"
 }
    ]

  })
}

resource "aws_api_gateway_rest_api" "main" {

  name        = "${var.project}-api-${var.environment}"

 endpoint_configuration {
    types = ["REGIONAL"]
  }


}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  provider_arns    = [aws_cognito_user_pool.main.arn]
}


resource "aws_iam_role" "lambda_role" {
 name = "lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
 Statement = [
 {
 Action = "sts:AssumeRole"
 Effect = "Allow"
 Principal = {
 Service = "lambda.amazonaws.com"
 }

 Sid    = ""
 }
 ]

  })
  tags = {
    Name        = "lambda-role"
    Environment = var.environment
    Project     = var.project
  }

}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda-dynamodb-policy-${var.environment}"


 policy = jsonencode({
    Version = "2012-10-17",
    Statement = [

      {
        Sid = "AllowDynamoDBAccess",
        Effect = "Allow",
 Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
 "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem"
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
        Action = [
 "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
 ],
 Effect = "Allow",
        Resource = "*"
      }
    ]
  })


}


resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {

  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
  role       = aws_iam_role.lambda_role.name

}

# Example Lambda function (replace with your actual function code)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../lambda_functions" # Replace with the path to your Lambda function code
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "add_item_lambda" {

  filename         = data.archive_file.lambda_zip.output_path
 function_name = "add_item_lambda-${var.environment}"
 handler = "index.handler"  # Replace with your handler function name
  memory_size = 1024
  publish       = true
  runtime       = "nodejs12.x"
  role          = aws_iam_role.lambda_role.arn

  timeout = 60
  tracing_config {
    mode = "Active"
  }
}


resource "aws_api_gateway_resource" "item_resource" {
 parent_id   = aws_api_gateway_rest_api.main.root_resource_id
 path_part = "item"
 rest_api_id = aws_api_gateway_rest_api.main.id
}


resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
 http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id


}



resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
 resource_id            = aws_api_gateway_resource.item_resource.id
 http_method           = aws_api_gateway_method.post_item.http_method
 integration_http_method = "POST"
 type                    = "aws_proxy"
 integration_subtype    = "Event"
 credentials            = aws_iam_role.lambda_role.arn
 request_templates = {
    "application/json" = jsonencode({statusCode = 200})
 }

 integration_uri = aws_lambda_function.add_item_lambda.invoke_arn


}





resource "aws_api_gateway_deployment" "main" {

 rest_api_id = aws_api_gateway_rest_api.main.id
  triggers = {
 always_run = timestamp()
 }
 lifecycle {
    create_before_destroy = true
 }
 depends_on = [aws_api_gateway_integration.post_item_integration]


}


resource "aws_api_gateway_stage" "prod" {
 deployment_id = aws_api_gateway_deployment.main.id
 rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"


}

resource "aws_amplify_app" "main" {
  name       = "${var.project}-amplify-${var.environment}"

  repository = "https://github.com/example/example-repo" # Replace with your repository URL

  build_spec = <<-EOT
version: 0.1
frontend:
  phases:
    preBuild:
 npm install
 build:
    commands:
      - npm run build
  artifacts:
 baseDirectory: /build
    files:
 - '**/*'
  cache:
    paths:
 - 'node_modules/**/*'

EOT

  tags = {
 Name = "${var.project}-amplify-${var.environment}"
  Environment = var.environment
 Project = var.project


  }


}

resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.environment}"

  assume_role_policy = jsonencode({
 Version = "2012-10-17"
    Statement = [
 {
 Action = "sts:AssumeRole"

 Effect = "Allow"
 Principal = {

 Service = "amplify.amazonaws.com"
 }
        Sid = ""

 }
    ]
  })

  tags = {

    Name = "amplify-role-${var.environment}"
 Environment = var.environment
    Project = var.project
  }

}

resource "aws_iam_policy" "amplify_policy" {
  name = "amplify-policy-${var.environment}"
  policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
 {
        Effect = "Allow",
        Action = [

          "amplify:*"
        ],

        Resource = "*"

      }

 ]
  })



}

resource "aws_iam_role_policy_attachment" "amplify_attachment" {
  policy_arn = aws_iam_policy.amplify_policy.arn
  role = aws_iam_role.amplify_role.name

}



resource "aws_amplify_branch" "master" {

 app_id      = aws_amplify_app.main.id
  branch_name = "master"
  enable_auto_build = true
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
  value = aws_api_gateway_deployment.main.invoke_url
}




output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


output "lambda_function_arn" {

  value = aws_lambda_function.add_item_lambda.arn
}


