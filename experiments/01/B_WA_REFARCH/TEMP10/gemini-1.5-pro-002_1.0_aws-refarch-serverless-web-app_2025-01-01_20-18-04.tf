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

variable "application_name" {
  type = string
}

variable "stack_name" {
  type = string
}


variable "github_repo_url" {
  type = string
}
variable "github_repo_branch" {
 type = string
 default = "master"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers  = false
    require_symbols  = false
    require_uppercase = true
  }

  username_attributes = ["email"]
  verification_message_template {
 default_email_options {
      delivery_failure_to = ["developer@example.com"]
 }
  }

 email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
    source_arn           = "arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:identity/developer@example.com"
  }

 auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name                                 = "${var.application_name}-${var.stack_name}-user-pool-client"
  user_pool_id                         = aws_cognito_user_pool.main.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Replace with actual callback URL
  logout_urls                         = ["http://localhost:3000/"] # Replace with actual logout URL
  supported_identity_providers         = ["COGNITO"]
}



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
    enabled     = true
    kms_key_arn = aws_kms_key.default.arn
  }


}



resource "aws_kms_key" "default" {
  description             = "Default KMS key"
 enable_key_rotation = true
}



data "aws_caller_identity" "current" {}


resource "aws_iam_role" "api_gateway_role" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
 Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
 Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}


resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.application_name}-${var.stack_name}-api-gateway-cloudwatch-policy"
  role = aws_iam_role.api_gateway_role.id


  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:PutLogEvents"
        ]
        Effect   = "Allow"
 Resource = "*"
      }
    ]
  })

}





resource "aws_apigatewayv2_api" "main" {
  name          = "${var.application_name}-${var.stack_name}-api"
  protocol_type = "HTTP"



}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.main.id
  name         = "prod"
 auto_deploy = true


 access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format          = jsonencode({
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
}





resource "aws_cloudwatch_log_group" "api_gateway" {
  name = "/aws/apigateway/${aws_apigatewayv2_api.main.name}-access-logs"
  retention_in_days = 30


}



resource "aws_lambda_function" "add_item" {
  filename                       = "add_item.zip" # replace with your lambda function zip file
 function_name = "${var.application_name}-${var.stack_name}-add-item"
  handler                = "index.handler"
  runtime                = "nodejs12.x" # Update to a supported runtime
  memory_size           = 1024
  timeout                = 60
  role                   = aws_iam_role.lambda_execution_role.arn
  publish = true
  tracing_config {
    mode = "Active"
  }
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

}




resource "aws_iam_role" "lambda_execution_role" {
 name = "${var.application_name}-${var.stack_name}-lambda-role"
 assume_role_policy = jsonencode({
 Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole"
 Effect = "Allow",
        Principal = {
 Service = "lambda.amazonaws.com"
        }
      }
    ]


  })


}


resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${var.application_name}-${var.stack_name}-lambda-dynamodb-policy"
 role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
 Action = [
          "dynamodb:PutItem",
 "dynamodb:GetItem",
          "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable",
          "dynamodb:ConditionCheckItem"
 ],
        Effect   = "Allow",
 Resource = aws_dynamodb_table.main.arn
      },
 {
 Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
 Effect = "Allow",
 Resource = "*"
      },

 {
        Action = [
 "cloudwatch:PutMetricData"
        ],
        Effect = "Allow",
 Resource = "*"
 }
    ]


  })
}





resource "aws_apigatewayv2_integration" "add_item_integration" {
  api_id             = aws_apigatewayv2_api.main.id
 integration_type   = "aws_proxy"
  integration_uri    = aws_lambda_function.add_item.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}



resource "aws_apigatewayv2_route" "add_item_route" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /item"
 target = "integrations/${aws_apigatewayv2_integration.add_item_integration.id}"
  authorization_type = "AWS_IAM"
}


# (Similar resources for Get Item, Get All Items, Update Item, Complete Item, and Delete Item Lambda functions, API Gateway Integrations and Routes should be added here)


resource "aws_amplify_app" "main" {
  name       = "${var.application_name}-${var.stack_name}-amplify-app"
  repository = var.github_repo_url
  build_spec = <<-EOF
version: 0.1
frontend:
  phases:
    preBuild:
      commands:
        - yarn install
    build:
      commands:
        - yarn build
  artifacts:
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
EOF
}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
  enable_auto_build = true
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
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "amplify_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.amplify_role.name

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

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}
