
# Provider and required version configurations remain unchanged
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

# Variables with added types and descriptions
variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "environment" {
  type        = string
  description = "Environment name for resource tagging"
  default     = "production"
}

variable "domain_name" {
  type        = string
  description = "Domain name for WordPress site"
}

variable "db_password" {
  type        = string
  description = "RDS database password"
  sensitive   = true
}

# Existing networking resources remain largely unchanged
# Added environment tag to resources missing it

resource "aws_security_group" "alb" {
  name        = "wordpress-alb-sg"
  description = "Security group for WordPress ALB"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Consider restricting to specific IPs
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-alb-sg"
    Environment = var.environment
  }
}

# Modified RDS instance with enhanced security
resource "aws_db_instance" "wordpress" {
  identifier           = "wordpress-db"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  db_name             = "wordpress"
  username            = "wordpress"
  password            = var.db_password
  skip_final_snapshot = true

  storage_encrypted               = true # Added encryption
  iam_database_authentication_enabled = true # Added IAM auth
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"] # Added logging

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name

  backup_retention_period = 7
  multi_az               = true

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
  }
}

# Modified ALB with security enhancements
resource "aws_lb" "wordpress" {
  name                       = "wordpress-alb"
  internal                   = false
  load_balancer_type        = "application"
  security_groups           = [aws_security_group.alb.id]
  subnets                   = aws_subnet.public[*].id
  enable_deletion_protection = true
  drop_invalid_header_fields = true

  tags = {
    Name        = "wordpress-alb"
    Environment = var.environment
  }
}

# Modified ALB listener to use HTTPS
resource "aws_lb_listener" "wordpress" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.wordpress.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

# Added WAF association
resource "aws_wafregional_web_acl_association" "wordpress" {
  resource_arn = aws_lb.wordpress.arn
  web_acl_id   = aws_wafregional_web_acl.wordpress.id
}

# Added Shield Advanced protection
resource "aws_shield_protection" "wordpress_alb" {
  name         = "wordpress-alb-protection"
  resource_arn = aws_lb.wordpress.arn
}

resource "aws_shield_protection" "wordpress_cloudfront" {
  name         = "wordpress-cloudfront-protection"
  resource_arn = aws_cloudfront_distribution.wordpress.arn
}

# Modified CloudFront distribution with security enhancements
resource "aws_cloudfront_distribution" "wordpress" {
  enabled     = true
  web_acl_id  = aws_wafv2_web_acl.cloudfront.arn
  price_class = "PriceClass_100"

  logging_config {
    include_cookies = false
    bucket         = aws_s3_bucket.logs.bucket_domain_name
    prefix         = "cloudfront/"
  }

  origin {
    domain_name = aws_lb.wordpress.dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = "wordpress-alb"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cloudfront.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  tags = {
    Name        = "wordpress-cdn"
    Environment = var.environment
  }
}

# Outputs with descriptions
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}

output "rds_endpoint" {
  description = "Endpoint of the RDS database instance"
  value       = aws_db_instance.wordpress.endpoint
}
