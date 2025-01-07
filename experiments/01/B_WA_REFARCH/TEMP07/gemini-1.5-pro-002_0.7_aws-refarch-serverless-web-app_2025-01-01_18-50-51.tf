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
  default = "us-east-1"
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "stack_name" {
  type = string
}

variable "github_repo_url" {
  type = string
}

variable "github_repo_branch" {
  type    = string
  default = "master"
}


resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
  }
  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_client" "main" {
  name = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"

 user_pool_id = aws_cognito_user_pool.main.id
  generate_secret = false

 allowed_oauth_flows_user_pool_client = true
 allowed_oauth_flows = ["authorization_code", "implicit"]

  allowed_scopes = ["email", "phone", "openid"]
  callback_urls = ["http://localhost:3000/"] # Placeholder, update as needed
  logout_urls = ["http://localhost:3000/"] # Placeholder, update as needed

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id
  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-user-pool-domain"
    Environment = var.environment
    Project     = var.project_name
  }
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
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-${var.environment}-${var.stack_name}-api"
 description = "API Gateway for ${var.project_name}"

  tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-api"
    Environment = var.environment
    Project     = var.project_name
  }
}



# Simplified Lambda function definition (replace with actual function code)

resource "aws_lambda_function" "example" {

  function_name = "my_function"
  handler = "index.handler"
  runtime = "nodejs12.x"
  role = aws_iam_role.lambda_exec_role.arn

# Replace with your actual function code
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
 memory_size = 1024
  timeout = 60
  tracing_config {
 mode = "Active"
  }
  tags = {
    Name        = "my_function"
    Environment = var.environment
    Project     = var.project_name
  }
}


resource "aws_iam_role" "lambda_exec_role" {
 name = "lambda_exec_role"
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

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_amplify_app" "main" {
 name = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-app"
 repository = var.github_repo_url
 access_token = "YOUR_GITHUB_ACCESS_TOKEN" # Replace with your GitHub access token or use a secrets management solution
 build_spec = jsonencode({
    version = 0.1,
    frontend = {
      phases = {
        preBuild  = "npm install",
        build     = "npm run build",
        postBuild = "npm run deploy"
      },
      artifacts = {
 baseDirectory = "/public",
        files = ["**/*"]
      },
      cache = {
 paths = ["node_modules/**/*"]
      }
    }
  })

 tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-app"
    Environment = var.environment
    Project     = var.project_name
  }
}



resource "aws_amplify_branch" "main" {
 app_id = aws_amplify_app.main.id
 branch_name = var.github_repo_branch
 enable_auto_build = true

 tags = {
    Name        = "${var.project_name}-${var.environment}-${var.stack_name}-amplify-branch"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "api_gateway_cloudwatch_role" {
  name = "api_gateway_cloudwatch_role"

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
