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

variable "application_name" {
  type    = string
  default = "todo-app"
}

variable "stack_name" {
  type    = string
  default = "todo-app-stack"
}



resource "aws_cognito_user_pool" "main" {
  name = "${var.application_name}-${var.stack_name}-user-pool"

  password_policy {
    minimum_length = 6
    require_lowercase = true
    require_uppercase = true
  }

 auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_cognito_user_pool_client" "main" {
  name                 = "${var.application_name}-${var.stack_name}-user-pool-client"
 user_pool_id        = aws_cognito_user_pool.main.id
  generate_secret      = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_scopes = ["phone", "email", "openid"]

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-client"
    Environment = var.environment
    Project     = var.project
  }
}



resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.application_name}-${var.stack_name}"
 user_pool_id = aws_cognito_user_pool.main.id

  tags = {
    Name        = "${var.application_name}-${var.stack_name}-user-pool-domain"
    Environment = var.environment
    Project     = var.project
  }
}



resource "aws_dynamodb_table" "main" {
  name           = "todo-table-${var.stack_name}"
 billing_mode    = "PROVISIONED"
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
  tags = {
        Name        = "lambda_role_${var.stack_name}"
        Environment = var.environment
        Project     = var.project
      }
}



resource "aws_iam_policy" "lambda_policy" {
 name = "lambda_policy_${var.stack_name}"


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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
 "dynamodb:BatchWriteItem",
          "dynamodb:Scan",
 "dynamodb:Query"
 ],
        Effect   = "Allow",
 Resource = [
 aws_dynamodb_table.main.arn
        ]
      },
      {
 Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ],
        Effect = "Allow",
        Resource = "*"
      },
      {
        Sid = "CloudWatchMetricsPermissions",
        Effect = "Allow",
        Action = [
            "cloudwatch:PutMetricData"
        ],
        Resource = "*"
    }

    ]
  })

}


resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
 policy_arn = aws_iam_policy.lambda_policy.arn
}



resource "aws_lambda_function" "add_item" {
  filename         = var.lambda_zip_file
 function_name = "add_item_${var.stack_name}"
  handler          = "index.handler"
  role             = aws_iam_role.lambda_role.arn
 runtime         = "nodejs12.x"
  memory_size      = 1024
 timeout          = 60
  source_code_hash = filebase64sha256(var.lambda_zip_file)

  tracing_config {
    mode = "Active"
  }

  tags = {
    Name        = "add_item_lambda_${var.stack_name}"
    Environment = var.environment
 Project     = var.project
  }

}


# Define additional Lambda functions (get_item, get_all_items, update_item, complete_item, delete_item) similarly
# ...


variable "lambda_zip_file" {
  type = string
  default = "./lambda_function.zip"

}



resource "aws_apigateway_rest_api" "main" {
  name        = "${var.application_name}-api-${var.stack_name}"


  tags = {
    Name        = "${var.application_name}-api-${var.stack_name}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_apigateway_authorizer" "cognito_authorizer" {

  name          = "cognito_authorizer_${var.stack_name}"
  rest_api_id   = aws_apigateway_rest_api.main.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.main.arn]
}

resource "aws_apigateway_resource" "item_resource" {
  rest_api_id = aws_apigateway_rest_api.main.id
  parent_id   = aws_apigateway_rest_api.main.root_resource_id
 path_part   = "item"
}


resource "aws_apigateway_resource" "item_id_resource" {
  rest_api_id = aws_apigateway_rest_api.main.id
 parent_id   = aws_apigateway_resource.item_resource.id
 path_part   = "{id}"
}


# Add API Gateway methods (POST /item, GET /item/{id}, GET /item, PUT /item/{id}, POST /item/{id}/done, DELETE /item/{id}) and integrate them with Lambda functions
# ...



resource "aws_apigateway_deployment" "main" {
  rest_api_id = aws_apigateway_rest_api.main.id
  stage_name  = "prod"

 depends_on = [
    # list all the API Gateway resources and methods here
  ]
}



resource "aws_apigateway_stage" "prod" {
  deployment_id = aws_apigateway_deployment.main.id
  rest_api_id   = aws_apigateway_rest_api.main.id
  stage_name    = "prod"

}



#Amplify App
resource "aws_amplify_app" "main" {
  name       = var.application_name
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
    baseDirectory: /build
    files:
      - '**/*'
EOF
  tags = {
    Name        = var.application_name
    Environment = var.environment
    Project     = var.project
  }
}

variable "github_repo" {
  type = string
 default = "https://github.com/<your-github-username>/<your-repo-name>.git" # Replace with your repository URL
}

resource "aws_amplify_branch" "master" {
 app_id      = aws_amplify_app.main.id
  branch_name = "master"
  enable_auto_build = true
}


#Outputs

output "cognito_user_pool_id" {
 value = aws_cognito_user_pool.main.id
}



output "cognito_user_pool_client_id" {
 value = aws_cognito_user_pool_client.main.id
}




output "api_gateway_invoke_url" {
 value = aws_apigateway_deployment.main.invoke_url
}


output "amplify_app_id" {
 value = aws_amplify_app.main.id
}


output "amplify_default_domain" {
 value = aws_amplify_app.main.default_domain
}


