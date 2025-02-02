terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
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

variable "github_repo" {
  type = string
  description = "GitHub repository for Amplify"
}

variable "github_branch" {
  type    = string
  default = "master"
}




resource "aws_cognito_user_pool" "main" {
  name = "${var.stack_name}-user-pool"
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_numbers = false
    require_symbols = false
    require_uppercase = true
  }

  tags = {
    Name        = "${var.stack_name}-user-pool"
    Environment = "prod"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.stack_name}-domain"
  user_pool_id = aws_cognito_user_pool.main.id
}



resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.stack_name}-user-pool-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["authorization_code", "implicit"]
  allowed_oauth_scopes                = ["email", "phone", "openid"]
  callback_urls                       = ["http://localhost:3000/"] # Placeholder - update as needed

  tags = {
    Name        = "${var.stack_name}-user-pool-client"
    Environment = "prod"
  }

}



resource "aws_dynamodb_table" "main" {
  name         = "todo-table-${var.stack_name}"
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
  }

}

resource "aws_iam_role" "lambda_role" {
 name = "lambda_role_${var.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "lambda_policy_${var.stack_name}"
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
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.main.arn
      },
      {
        Action = [
 "logs:CreateLogGroup",
          "logs:CreateLogStream",
 "logs:PutLogEvents",
        ],
        Effect   = "Allow",
        Resource = "*"
      },
 {
        Effect = "Allow",
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ],
        Resource = "*"
      },
 ]
  })
}


resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


resource "aws_lambda_function" "add_item" { # Example - Repeat for other functions
  function_name = "${var.stack_name}-add-item"
  filename      = "../lambda_functions/add_item.zip" # Placeholder - update as needed
  source_code_hash = filebase64sha256("../lambda_functions/add_item.zip")
 role = aws_iam_role.lambda_role.arn
  handler = "index.handler" # Placeholder - update as needed
  runtime = "nodejs12.x"
  memory_size = 1024
  timeout = 60
  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "${var.stack_name}-add-item"
    Environment = "prod"
  }
}



resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.stack_name}-api"

  tags = {
    Name        = "${var.stack_name}-api"
    Environment = "prod"
  }
}


resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name            = "cognito_authorizer"
  type            = "COGNITO_USER_POOLS"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  provider_arns   = [aws_cognito_user_pool.main.arn]
}

# Example Resource and Method for Add Item - repeat for other methods and resources
resource "aws_api_gateway_resource" "item_resource" {
 rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "add_item_method" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.item_resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
 authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id

}



resource "aws_api_gateway_integration" "add_item_integration" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.item_resource.id
  http_method             = aws_api_gateway_method.add_item_method.http_method
  integration_http_method = "POST"
  type                    = "aws_proxy"
  integration_subtype = "Event"
  credentials = aws_iam_role.lambda_role.arn

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_amplify_app" "main" {
  name       = var.stack_name
  repository = var.github_repo
  access_token = "YOUR_GITHUB_PERSONAL_ACCESS_TOKEN" # Replace with actual token from GitHub settings
 build_spec = jsonencode({
    version = 1,
    frontend = {
 phases = {
        preBuild  = "npm install",
 build = "npm run build"
 }
      artifacts = {
 baseDirectory = "/dist", # Update if needed
 files = ["**/*"]
 }
    }
  })

  tags = {
    Name        = var.stack_name
    Environment = "prod"
  }
}

resource "aws_amplify_branch" "master" {
  app_id      = aws_amplify_app.main.id
  branch_name = var.github_branch
  enable_auto_build = true
}


# IAM role and policy for API Gateway logging
resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "${var.stack_name}-api-gateway-cw-role"
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




#Outputs

output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.main.name
}

output "api_gateway_id" {
 value = aws_api_gateway_rest_api.main.id
}

output "amplify_app_id" {
  value = aws_amplify_app.main.id
}


