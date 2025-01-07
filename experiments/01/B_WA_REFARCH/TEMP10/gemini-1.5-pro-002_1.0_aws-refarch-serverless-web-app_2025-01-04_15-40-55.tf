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
  default = "us-east-1"
}

variable "stack_name" {
  type    = string
  default = "serverless-todo-app"
}

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "github_repository" {
  type    = string
  default = "your-github-repository" # Replace with your GitHub repository
}

variable "github_branch" {
  type    = string
  default = "main"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-user-pool-${var.stack_name}"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  username_attributes = ["email"]
  verification_message_template {
    email_message = "Your verification code is {####}"
    email_subject = "Welcome to ${var.application_name}"
  }

  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
}


resource "aws_cognito_user_pool_client" "main" {
  name = "${var.application_name}-client-${var.stack_name}"

  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows          = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes        = ["email", "phone", "openid"]

  callback_urls = ["http://localhost:3000"] # Placeholder - Update with your callback URLs
  logout_urls = ["http://localhost:3000"] # Placeholder - Update with your logout URLs

  supported_identity_providers = ["COGNITO"]

 refresh_token_validity = 30 # in days
}



resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
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

  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.application_name
  }
}




resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"
  description = "API Gateway for ${var.application_name}"
}


resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"

  depends_on = [
    aws_api_gateway_integration.get_item,
    aws_api_gateway_integration.get_items,
    aws_api_gateway_integration.add_item,
    aws_api_gateway_integration.update_item,
    aws_api_gateway_integration.complete_item,
    aws_api_gateway_integration.delete_item
 ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = "prod"
  deployment_id = aws_api_gateway_deployment.main.id

  tags = {
    Name = "prod"
  }
}

resource "aws_api_gateway_usage_plan" "main" {
  name        = "${var.application_name}-usage-plan"
 product_code = "free"


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


resource "aws_api_gateway_usage_plan_key" "main" {
  usage_plan_id = aws_api_gateway_usage_plan.main.id
  key_id        = aws_api_gateway_api_key.main.id
  key_type      = "API_KEY"
}

resource "aws_api_gateway_api_key" "main" {
  name = "${var.application_name}-api-key"
}


resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api-gateway-cloudwatch-role-${var.stack_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
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
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:GetLogEvents",
                "logs:FilterLogEvents"
            ],
            "Resource": "*"
        }
    ]
}



EOF
}


resource "aws_api_gateway_account" "main" {
 cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch_role.arn
}


resource "aws_lambda_function" "add_item" {
  function_name = "add-item-${var.stack_name}"
  handler = "index.handler" # Update with your Lambda function handler
  runtime = "nodejs12.x"
 memory_size = 1024
  timeout = 60

# Replace with your actual code location
filename         = "lambda_functions.zip"
  source_code_hash = filebase64sha256("lambda_functions.zip")

  role = aws_iam_role.lambda_exec_role.arn

  tracing_config {
    mode = "ACTIVE"
  }

 environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  tags = {
    Name = "add-item-lambda-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }
}


resource "aws_lambda_function" "get_item" {
  function_name = "get-item-${var.stack_name}"
  handler = "index.handler" # Update with your Lambda function handler
 runtime = "nodejs12.x"
  memory_size = 1024
  timeout = 60


 filename         = "lambda_functions.zip"
  source_code_hash = filebase64sha256("lambda_functions.zip")


  role = aws_iam_role.lambda_exec_role.arn

  tracing_config {
    mode = "ACTIVE"
  }

 environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }

  tags = {

    Name = "get-item-lambda-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name
  }
}

resource "aws_lambda_function" "get_items" {

  function_name = "get-items-${var.stack_name}"

  handler = "index.handler" # Update with your Lambda function handler

 runtime = "nodejs12.x"
  memory_size = 1024
  timeout = 60

  filename         = "lambda_functions.zip"
  source_code_hash = filebase64sha256("lambda_functions.zip")
  role = aws_iam_role.lambda_exec_role.arn


  tracing_config {
    mode = "ACTIVE"
  }


 environment {
    variables = {

      TABLE_NAME = aws_dynamodb_table.main.name

    }
  }
  tags = {

    Name = "get-items-lambda-${var.stack_name}"

    Environment = "prod"
    Project = var.application_name

  }
}

resource "aws_lambda_function" "update_item" {

  function_name = "update-item-${var.stack_name}"
  handler = "index.handler" # Update with your Lambda function handler
 runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60


  filename         = "lambda_functions.zip"
  source_code_hash = filebase64sha256("lambda_functions.zip")


  role = aws_iam_role.lambda_exec_role.arn


  tracing_config {
 mode = "ACTIVE"
  }

 environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.main.name
    }
  }


  tags = {
    Name = "update-item-lambda-${var.stack_name}"
    Environment = "prod"
    Project = var.application_name

  }
}


resource "aws_lambda_function" "complete_item" {
  function_name = "complete-item-${var.stack_name}"
  handler = "index.handler" # Update with your Lambda function handler

 runtime = "nodejs12.x"

 memory_size = 1024

 timeout = 60

  filename         = "lambda_functions.zip"

  source_code_hash = filebase64sha256("lambda_functions.zip")

  role = aws_iam_role.lambda_exec_role.arn

  tracing_config {

 mode = "ACTIVE"

  }

 environment {

 variables = {

 TABLE_NAME = aws_dynamodb_table.main.name

 }

 }
  tags = {

    Name = "complete-item-lambda-${var.stack_name}"

    Environment = "prod"

 Project = var.application_name

 }

}



resource "aws_lambda_function" "delete_item" {

  function_name = "delete-item-${var.stack_name}"
  handler = "index.handler" # Update with your Lambda function handler

 runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60


  filename         = "lambda_functions.zip"

  source_code_hash = filebase64sha256("lambda_functions.zip")



  role = aws_iam_role.lambda_exec_role.arn

  tracing_config {
 mode = "ACTIVE"

  }

 environment {

    variables = {

      TABLE_NAME = aws_dynamodb_table.main.name

 }

  }
  tags = {

 Name = "delete-item-lambda-${var.stack_name}"

 Environment = "prod"

 Project = var.application_name

  }

}




resource "aws_iam_role" "lambda_exec_role" {

  name = "lambda-exec-role-${var.stack_name}"

 assume_role_policy = <<EOF

{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Effect": "Allow",
   "Principal": {
    "Service": "lambda.amazonaws.com"
   },
   "Action": "sts:AssumeRole"
  }
 ]

}
EOF
}


resource "aws_iam_role_policy" "lambda_dynamodb_policy" {

 name = "lambda-dynamodb-policy-${var.stack_name}"
 role = aws_iam_role.lambda_exec_role.id

 policy = <<EOF

{

 "Version": "2012-10-17",
 "Statement": [
 {
 "Effect": "Allow",
 "Action": [
 "dynamodb:GetItem",
 "dynamodb:PutItem",
 "dynamodb:UpdateItem",
 "dynamodb:DeleteItem",
 "dynamodb:Scan",
 "dynamodb:Query",
 "dynamodb:BatchWriteItem",
 "dynamodb:BatchGetItem"
 ],

 "Resource": aws_dynamodb_table.main.arn
 },
 {

 "Effect": "Allow",
 "Action": [
  "logs:CreateLogGroup",

  "logs:CreateLogStream",

  "logs:PutLogEvents"
 ],

 "Resource": "arn:aws:logs:*:*:*"
 }

 ]

}


EOF

}






resource "aws_api_gateway_authorizer" "cognito_authorizer" {

 name = "cognito-authorizer-${var.stack_name}"

 provider_arns = [aws_cognito_user_pool.main.arn]

 rest_api_id = aws_api_gateway_rest_api.main.id

 type = "COGNITO_USER_POOLS"
}


resource "aws_api_gateway_resource" "item_resource" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 parent_id = aws_api_gateway_rest_api.main.root_resource_id
 path_part = "item"
}

resource "aws_api_gateway_resource" "item_id_resource" {

 rest_api_id = aws_api_gateway_rest_api.main.id
 parent_id = aws_api_gateway_resource.item_resource.id
 path_part = "{id}"

}


resource "aws_api_gateway_method" "get_items_method" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_resource.id
 http_method = "GET"
 authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}


resource "aws_api_gateway_integration" "get_items" {

 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_resource.id
 http_method = "GET"
 integration_http_method = "POST"
 type = "aws_proxy"
 integration_type = "aws_proxy"


 integration_subtype = "Event"

 request_templates = {
   "application/json" = <<EOF
{
  "cognito-username": "$${request.authorizer.claims['cognito:username']}"
}
EOF

 }
 content_handling = "CONVERT_TO_BINARY"

 passthrough_behavior = "WHEN_NO_TEMPLATES"



 timeout_milliseconds = 29000
 credentials = aws_iam_role.lambda_exec_role.arn
 request_parameters = {
 "integration.request.path.id" = "method.request.path.id"

 }

 integration_uri = aws_lambda_function.get_items.invoke_arn
}


resource "aws_api_gateway_method" "get_item_method" {

 rest_api_id = aws_api_gateway_rest_api.main.id

 resource_id = aws_api_gateway_resource.item_id_resource.id
 http_method = "GET"
 authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "get_item" {

 rest_api_id = aws_api_gateway_rest_api.main.id

 resource_id = aws_api_gateway_resource.item_id_resource.id
 http_method = "GET"
 integration_http_method = "POST"
 type = "aws_proxy"
 integration_type = "aws_proxy"
 integration_subtype = "Event"
 request_templates = {

 "application/json" = <<EOF
{
 "cognito-username": "$${request.authorizer.claims['cognito:username']}",
 "id": "$${request.path.id}"
}
EOF

 }

 content_handling = "CONVERT_TO_BINARY"
 passthrough_behavior = "WHEN_NO_TEMPLATES"



 timeout_milliseconds = 29000

 credentials = aws_iam_role.lambda_exec_role.arn

 request_parameters = {

 "integration.request.path.id" = "method.request.path.id"

 }

 integration_uri = aws_lambda_function.get_item.invoke_arn
}




resource "aws_api_gateway_method" "add_item_method" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_resource.id
 http_method = "POST"
 authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}


resource "aws_api_gateway_integration" "add_item" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_resource.id
 http_method = "POST"

 integration_http_method = "POST"

 type = "aws_proxy"
 integration_type = "aws_proxy"

 integration_subtype = "Event"

 request_templates = {
 "application/json" = <<EOF

{
  "cognito-username": "$${request.authorizer.claims['cognito:username']}",
  "body": $${request.body}
}

EOF

 }
 content_handling = "CONVERT_TO_BINARY"
 passthrough_behavior = "WHEN_NO_TEMPLATES"



 timeout_milliseconds = 29000

 credentials = aws_iam_role.lambda_exec_role.arn

 request_parameters = {

  "integration.request.path.id" = "method.request.path.id"

 }

 integration_uri = aws_lambda_function.add_item.invoke_arn

}


resource "aws_api_gateway_method" "update_item_method" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_id_resource.id
 http_method = "PUT"

 authorization = "COGNITO_USER_POOLS"

 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}




resource "aws_api_gateway_integration" "update_item" {

 rest_api_id = aws_api_gateway_rest_api.main.id

 resource_id = aws_api_gateway_resource.item_id_resource.id

 http_method = "PUT"

 integration_http_method = "POST"

 type = "aws_proxy"

 integration_type = "aws_proxy"

 integration_subtype = "Event"

 request_templates = {
 "application/json" = <<EOF
{
 "cognito-username": "$${request.authorizer.claims['cognito:username']}",
 "id": "$${request.path.id}",
  "body": $${request.body}
}

EOF

 }

 content_handling = "CONVERT_TO_BINARY"

 passthrough_behavior = "WHEN_NO_TEMPLATES"



 timeout_milliseconds = 29000


 credentials = aws_iam_role.lambda_exec_role.arn


 request_parameters = {

 "integration.request.path.id" = "method.request.path.id"

 }


 integration_uri = aws_lambda_function.update_item.invoke_arn

}




resource "aws_api_gateway_method" "complete_item_method" {

 rest_api_id = aws_api_gateway_rest_api.main.id

 resource_id = aws_api_gateway_resource.item_id_resource.id

 http_method = "POST"
 authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}




resource "aws_api_gateway_integration" "complete_item" {

 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_id_resource.id

 http_method = "POST"

 integration_http_method = "POST"

 type = "aws_proxy"


 integration_type = "aws_proxy"


 integration_subtype = "Event"

 request_templates = {

 "application/json" = <<EOF
{

 "cognito-username": "$${request.authorizer.claims['cognito:username']}",

 "id": "$${request.path.id}"

}

EOF
 }


 content_handling = "CONVERT_TO_BINARY"
 passthrough_behavior = "WHEN_NO_TEMPLATES"

 timeout_milliseconds = 29000
 credentials = aws_iam_role.lambda_exec_role.arn


 request_parameters = {
 "integration.request.path.id" = "method.request.path.id"
 }


 integration_uri = aws_lambda_function.complete_item.invoke_arn

}





resource "aws_api_gateway_method" "delete_item_method" {

 rest_api_id = aws_api_gateway_rest_api.main.id

 resource_id = aws_api_gateway_resource.item_id_resource.id

 http_method = "DELETE"
 authorization = "COGNITO_USER_POOLS"


 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

}


resource "aws_api_gateway_integration" "delete_item" {
 rest_api_id = aws_api_gateway_rest_api.main.id
 resource_id = aws_api_gateway_resource.item_id_resource.id

 http_method = "DELETE"
 integration_http_method = "POST"


 type = "aws_proxy"

 integration_type = "aws_proxy"

 integration_subtype = "Event"

 request_templates = {

 "application/json" = <<EOF
{
 "cognito-username": "$${request.authorizer.claims['cognito:username']}",

 "id": "$${request.path.id}"
}
EOF
 }

 content_handling = "CONVERT_TO_BINARY"
 passthrough_behavior = "WHEN_NO_TEMPLATES"


 timeout_milliseconds = 29000

 credentials = aws_iam_role.lambda_exec_role.arn

 request_parameters = {
  "integration.request.path.id" = "method.request.path.id"
 }


 integration_uri = aws_lambda_function.delete_item.invoke_arn
}



resource "aws_amplify_app" "main" {
 name = "${var.application_name}-amplify-${var.stack_name}"
 repository = var.github_repository
 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub Personal Access Token
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
  baseDirectory: /build
  files:
   - '**/*'
EOF
}


resource "aws_amplify_branch" "master" {

 app_id = aws_amplify_app.main.id
 branch_name = var.github_branch
 enable_auto_build = true


}


resource "aws_iam_role" "amplify_role" {
  name = "amplify-role-${var.stack_name}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "amplify.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}




resource "aws_iam_role_policy" "amplify_policy" {
 name = "amplify-policy-${var.stack_name}"
 role = aws_iam_role.amplify_role.id


 policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
  {
   "Effect": "Allow",
   "Action": [
 "amplify:*"

   ],
 "Resource": "*"

  }

 ]
}
EOF
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

output "amplify_default_domain" {
  value = aws_amplify_app.main.default_domain
}
