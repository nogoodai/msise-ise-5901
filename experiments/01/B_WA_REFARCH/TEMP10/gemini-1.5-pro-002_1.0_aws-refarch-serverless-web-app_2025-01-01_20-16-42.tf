terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
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

variable "project_name" {
  type = string
  default = "todo-app"
}

variable "environment" {
  type = string
  default = "dev"
}

variable "stack_name" {
  type = string
  default = "todo-app-stack"
}

variable "github_repo_url" {
  type = string
  default = "https://github.com/your-username/your-repo" # Replace with your actual GitHub repository URL
}

variable "github_repo_branch" {
  type = string
  default = "main"
}

# Cognito User Pool
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool-${var.environment}"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
    require_numbers = false
    require_symbols = false
  }

  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  name         = "${var.project_name}-user-pool-client-${var.environment}"

  generate_secret = false

  oauth_flows = [
    "authorization_code",
    "implicit"
  ]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                = ["email", "phone", "openid"]

  tags = {
    Name        = "${var.project_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project_name
  }
}


# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${var.stack_name}"
  user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.project_name}-user-pool-domain"
    Environment = var.environment
    Project     = var.project_name
  }
}

# DynamoDB Table
resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode = "PROVISIONED"
  read_capacity = 5
 write_capacity = 5
 hash_key = "cognito-username"
  attribute {
    name = "cognito-username"
    type = "S"
  }
 range_key = "id"
  attribute {
    name = "id"
 type = "S"
  }
 server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = "${var.project_name}-dynamodb-table"
    Environment = var.environment
    Project     = var.project_name
  }
}


# IAM Role for Lambda to access DynamoDB and CloudWatch
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

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
    Name        = "${var.project_name}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
 name = "${var.project_name}-lambda-policy-${var.environment}"

 policy = jsonencode({
 Version = "2012-10-17",
    Statement = [


      {
        Effect = "Allow",
 Action = [
          "dynamodb:PutItem",
 "dynamodb:GetItem",
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
 Resource = "arn:aws:logs:*:*:*"
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

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Placeholder for Lambda functions (replace with actual function code)
resource "aws_lambda_function" "example_lambda" {
  function_name = "${var.project_name}-example-lambda-${var.environment}"
  handler = "index.handler" # Replace with actual handler
  role = aws_iam_role.lambda_role.arn
 runtime = "nodejs12.x"
 memory_size = 1024
 timeout = 60
  tracing_config {
 mode = "Active"
  }

  # Replace with your actual function code
  filename      = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip") # Dummy file for demonstration

  tags = {
    Name = "${var.project_name}-example-lambda"
 Environment = var.environment
    Project = var.project_name
  }
}

# Amplify App

resource "aws_amplify_app" "main" {

 name = "${var.project_name}-amplify-app-${var.environment}"

 repository = var.github_repo_url

  tags = {
 Name = "${var.project_name}-amplify-app"
    Environment = var.environment
 Project = var.project_name
 }

}


resource "aws_amplify_branch" "master" {
  app_id = aws_amplify_app.main.id
  branch_name = var.github_repo_branch
 enable_auto_build = true


  tags = {
    Name = "${var.project_name}-amplify-branch"
 Environment = var.environment
 Project = var.project_name
  }

}



# API Gateway (Simplified - Needs expansion for full functionality)
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api-${var.environment}"
  protocol_type = "HTTP"


  tags = {
 Name = "${var.project_name}-api"
    Environment = var.environment
 Project = var.project_name
  }
}


# IAM Role for API Gateway to log to CloudWatch

resource "aws_iam_role" "api_gateway_role" {
  name = "${var.project_name}-api-gateway-role-${var.environment}"
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
    Name        = "${var.project_name}-api-gateway-role"
 Environment = var.environment
 Project = var.project_name
 }
}



resource "aws_iam_policy" "api_gateway_cloudwatch_policy" {
  name = "${var.project_name}-api-gateway-cloudwatch-policy-${var.environment}"
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

}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch_attachment" {
  role       = aws_iam_role.api_gateway_role.name
 policy_arn = aws_iam_policy.api_gateway_cloudwatch_policy.arn


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


output "amplify_app_id" {
 value = aws_amplify_app.main.id
}

output "api_gateway_id" {
 value = aws_apigatewayv2_api.main.id

}
