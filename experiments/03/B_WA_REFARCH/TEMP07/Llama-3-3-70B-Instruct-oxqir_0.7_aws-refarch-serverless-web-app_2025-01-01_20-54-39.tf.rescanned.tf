provider "aws" {
  region = "us-west-2"
  version = "5.1.0"
}

variable "stack_name" {
  type = string
  default = "serverless-web-app"
  description = "The name of the stack"
}

variable "application_name" {
  type = string
  default = "todo-app"
  description = "The name of the application"
}

resource "aws_cognito_user_pool" "user_pool" {
  name                = "${var.application_name}-user-pool"
  email_verification_message = "Your verification code is {####}."
  email_verification_subject = "Your verification code"
  alias_attributes = ["email"]
  auto_verified_attributes = ["email"]
  password_policy {
    minimum_length = 6
    require_uppercase = true
    require_lowercase = true
    require_symbols = false
    require_numbers = false
  }
  mfa_configuration = "OFF"
  tags = {
    Name        = "${var.application_name}-user-pool"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name                = "${var.application_name}-user-pool-client"
  user_pool_id       = aws_cognito_user_pool.user_pool.id
  generate_secret     = false
  allowed_oauth_flows = ["authorization_code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = ["email", "phone", "openid"]
  callback_urls       = ["https://${var.application_name}.${aws_route53_zone.zone.name}/"]
  logout_urls         = ["https://${var.application_name}.${aws_route53_zone.zone.name}/"]
  supported_identity_providers = ["COGNITO"]
  tags = {
    Name        = "${var.application_name}-user-pool-client"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_cognito_user_pool_domain" "user_pool_domain" {
  domain       = var.application_name
  user_pool_id = aws_cognito_user_pool.user_pool.id
  depends_on   = [aws_route53_record.validation]
}

resource "aws_route53_zone" "zone" {
  name = var.application_name
  tags = {
    Name        = var.application_name
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_route53_record" "validation" {
  name    = "_cognito-${aws_cognito_user_pool.user_pool.id}"
  type    = "CNAME"
  zone_id = aws_route53_zone.zone.id
  records = [aws_cloudfront_distribution.cognito_distribution.domain_name]
  ttl     = 300
}

resource "aws_cloudfront_distribution" "cognito_distribution" {
  origin {
    domain_name = aws_cognito_user_pool_domain.user_pool_domain.cloudfront_distribution_domain_name
    origin_id   = "cognito"
  }
  enabled = true
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "cognito"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "https-only"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cognito_cert.arn
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }
  logging_config {
    bucket = aws_s3_bucket.cloudfront_logs.id
    prefix = "/cloudfront-logs/"
  }
  tags = {
    Name        = "${var.application_name}-cognito-distribution"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "${var.application_name}-cloudfront-logs"
  acl    = "private"
  tags = {
    Name        = "${var.application_name}-cloudfront-logs"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_acm_certificate" "cognito_cert" {
  domain_name       = var.application_name
  validation_method = "DNS"
  tags = {
    Name        = "${var.application_name}-cognito-cert"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_route53_record" "cert_validation" {
  name    = aws_acm_certificate.cognito_cert.domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.cognito_cert.domain_validation_options[0].resource_record_type
  zone_id = aws_route53_zone.zone.id
  records = [aws_acm_certificate.cognito_cert.domain_validation_options[0].resource_record_value]
  ttl     = 300
}

resource "aws_dynamodb_table" "todo_table" {
  name           = "todo-table-${var.stack_name}"
  billing_mode   = "PROVISIONED"
  read_capacity_units  = 5
  write_capacity_units = 5
  attribute {
    name = "cognito-username"
    type = "S"
  }
  attribute {
    name = "id"
    type = "S"
  }
  key_schema = [
    {
      attribute_name = "cognito-username"
      key_type       = "HASH"
    },
    {
      attribute_name = "id"
      key_type       = "RANGE"
    }
  ]
  table_status = "ACTIVE"
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }
  tags = {
    Name        = "todo-table-${var.stack_name}"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "${var.application_name}-api"
  description = "API for ${var.application_name}"
  minimum_compression_size = 0
  tags = {
    Name        = "${var.application_name}-api"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "item"
}

resource "aws_api_gateway_method" "get_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
  api_key_required = true
}

resource "aws_api_gateway_method" "post_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
  api_key_required = true
}

resource "aws_api_gateway_method" "put_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "PUT"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
  api_key_required = true
}

resource "aws_api_gateway_method" "delete_item" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.authorizer.id
  api_key_required = true
}

resource "aws_api_gateway_integration" "get_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "post_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.post_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "put_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.put_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.put_item.arn}/invocations"
}

resource "aws_api_gateway_integration" "delete_item_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.delete_item.http_method
  integration_http_method = "POST"
  type        = "LAMBDA"
  uri         = "arn:aws:apigateway:${aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.delete_item.arn}/invocations"
}

resource "aws_api_gateway_authorizer" "authorizer" {
  name           = "${var.application_name}-authorizer"
  rest_api_id    = aws_api_gateway_rest_api.api.id
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  type           = "COGNITO_USER_POOLS"
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on  = [aws_api_gateway_integration.get_item_integration, aws_api_gateway_integration.post_item_integration, aws_api_gateway_integration.put_item_integration, aws_api_gateway_integration.delete_item_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
  description = "Deployment for ${var.application_name} API"
}

resource "aws_lambda_function" "get_item" {
  filename      = "get-item.zip"
  function_name = "${var.application_name}-get-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.application_name}-get-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "post_item" {
  filename      = "post-item.zip"
  function_name = "${var.application_name}-post-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.application_name}-post-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "put_item" {
  filename      = "put-item.zip"
  function_name = "${var.application_name}-put-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.application_name}-put-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_lambda_function" "delete_item" {
  filename      = "delete-item.zip"
  function_name = "${var.application_name}-delete-item"
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  role          = aws_iam_role.lambda_exec.arn
  tracing_config {
    mode = "Active"
  }
  tags = {
    Name        = "${var.application_name}-delete-item"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role" "lambda_exec" {
  name        = "${var.application_name}-lambda-exec"
  description = "Execution role for ${var.application_name} lambdas"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
  tags = {
    Name        = "${var.application_name}-lambda-exec"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.application_name}-lambda-policy"
  description = "Policy for ${var.application_name} lambdas"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Effect = "Allow"
        Resource = aws_dynamodb_table.todo_table.arn
      },
    ]
  })
  tags = {
    Name        = "${var.application_name}-lambda-policy"
    Environment = "prod"
    Project     = var.stack_name
  }
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name        = "${var.application_name}-usage-plan"
  description = "Usage plan for ${var.application_name} API"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }
  quota {
    limit  = 5000
    offset = 2
    period = "DAY"
  }
  throttle {
    burst_limit = 100
    rate_limit  = 50
  }
  tags = {
    Name        = "${var.application_name}-usage-plan"
    Environment = "prod"
    Project     = var.stack_name
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
  description = "The ID of the Cognito user pool"
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
  description = "The ID of the Cognito user pool client"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.todo_table.name
  description = "The name of the DynamoDB table"
}

output "api_gateway_id" {
  value = aws_api_gateway_rest_api.api.id
  description = "The ID of the API Gateway"
}

output "lambda_function_names" {
  value = [
    aws_lambda_function.get_item.function_name,
    aws_lambda_function.post_item.function_name,
    aws_lambda_function.put_item.function_name,
    aws_lambda_function.delete_item.function_name,
  ]
  description = "The names of the Lambda functions"
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
  description = "The ID of the Amplify app"
}

output "amplify_branch_name" {
  value = aws_amplify_branch.branch.branch_name
  description = "The name of the Amplify branch"
}
