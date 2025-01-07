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
  type    = string
  default = "us-west-2"
}

variable "stack_name" {
  type    = string
  default = "todo-app"
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

  verification_message_template {
    default_email_options {
      email_message = "Your verification code is {####}"
      email_subject = "Welcome to ${var.stack_name}"
    }
  }

  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                 = true
    name                    = "email"
    required                = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

 username_attributes = ["email"]
 auto_verified_attributes = ["email"]

}



resource "aws_cognito_user_pool_client" "client" {
  name = "${var.stack_name}-user-pool-client"

  user_pool_id = aws_cognito_user_pool.main.id

 allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  generate_secret = false

  callback_urls        = ["http://localhost:3000/"] # Placeholder, replace with your frontend callback URL
  logout_urls          = ["http://localhost:3000/"] # Placeholder, replace with your frontend logout URL
  supported_identity_providers = ["COGNITO"]


}




resource "aws_cognito_user_pool_domain" "main" {
 domain = "${var.stack_name}-${random_id.id.hex}"
 user_pool_id = aws_cognito_user_pool.main.id
}


resource "random_id" "id" {
  byte_length = 2
}


resource "aws_dynamodb_table" "todo_table" {
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
    Name = "todo-table-${var.stack_name}"
  }
}



resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-${var.stack_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}



resource "aws_iam_role_policy" "api_gateway_cloudwatch_policy" {
 name = "api-gateway-cloudwatch-policy-${var.stack_name}"
  role = aws_iam_role.api_gateway_cloudwatch_role.id


  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF

}


resource "aws_apigatewayv2_api" "main" {
 name          = "todo-api-${var.stack_name}"
 protocol_type = "HTTP"


}


resource "aws_lambda_permission" "api_gateway_invoke_lambda" {

  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.todo_lambda.function_name
 principal    = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.main.execution_arn}/*/*"

}


resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.stack_name}"


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
}

resource "aws_iam_policy" "lambda_policy" {
 name = "lambda-policy-${var.stack_name}"



 policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },

 {
      "Effect": "Allow",
      "Action": [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
          "dynamodb:Scan",
 "dynamodb:Query"
      ],
      "Resource": "*"

    }


  ]
}

EOF
}



resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
 policy_arn = aws_iam_policy.lambda_policy.arn
  role       = aws_iam_role.lambda_role.name

}


resource "aws_lambda_function" "todo_lambda" { # Example function, replace with your actual function code and configurations
 filename      = "lambda_function.zip" # Replace with your Lambda function zip file
 function_name = "todo-lambda-${var.stack_name}"
  handler       = "index.handler"
 runtime = "nodejs12.x"
 role = aws_iam_role.lambda_role.arn
 memory_size = 1024
 timeout = 60
  source_code_hash = filebase64sha256("lambda_function.zip") # Calculate the hash of your zip file

  tracing_config {
    mode = "Active"
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
 api_id = aws_apigatewayv2_api.main.id

 integration_type = "aws_proxy"
 integration_uri = aws_lambda_function.todo_lambda.invoke_arn
 integration_method = "POST"
  payload_format_version = "2.0"


}



resource "aws_apigatewayv2_route" "get_item_route" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /item/{id}"
 target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"

}


resource "aws_apigatewayv2_route" "get_all_items_route" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /item"
 target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_route" "add_item_route" {
  api_id    = aws_apigatewayv2_api.main.id
 route_key = "POST /item"
  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}




resource "aws_apigatewayv2_route" "update_item_route" {
 api_id    = aws_apigatewayv2_api.main.id
 route_key = "PUT /item/{id}"
 target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}



resource "aws_apigatewayv2_route" "complete_item_route" {
 api_id    = aws_apigatewayv2_api.main.id

  route_key = "POST /item/{id}/done"
 target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}


resource "aws_apigatewayv2_route" "delete_item_route" {
 api_id    = aws_apigatewayv2_api.main.id

  route_key = "DELETE /item/{id}"
 target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"

}


resource "aws_apigatewayv2_stage" "prod" {
 api_id = aws_apigatewayv2_api.main.id
 name        = "prod"
 auto_deploy = true

 access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({
      requestId = "$context.requestId"
      ip        = "$context.identity.sourceIp"
      caller    = "$context.identity.caller"
 user       = "$context.identity.user"

      requestTime = "$context.requestTime"
      httpMethod  = "$context.httpMethod"
 routeKey    = "$context.routeKey"
      status     = "$context.status"
 protocol    = "$context.protocol"
 responseLength = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"

    })

  }
}


resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/apigateway/${aws_apigatewayv2_api.main.name}"

  retention_in_days = 30

}



resource "aws_amplify_app" "main" {
 name       = "${var.stack_name}-amplify-app"
 repository = var.github_repo

  build_spec = <<YAML
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
 baseDirectory: build
 files:
 - '**/*'
YAML

}


resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
 branch_name = var.github_branch
  enable_auto_build = true


}

output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}


output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.client.id
}

output "api_gateway_url" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}

output "cognito_domain" {
  value = aws_cognito_user_pool_domain.main.domain
}
