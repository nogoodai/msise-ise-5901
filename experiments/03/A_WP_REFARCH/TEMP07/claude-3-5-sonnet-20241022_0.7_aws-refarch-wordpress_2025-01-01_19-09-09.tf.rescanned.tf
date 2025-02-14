
# Provider and terraform configuration remain unchanged
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

variable "environment" {
  type        = string
  description = "Environment name for resource tagging"
  default     = "production"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  type        = list(string)
  description = "List of public subnet CIDR blocks"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type        = list(string)
  description = "List of private subnet CIDR blocks"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "domain_name" {
  type        = string
  description = "Domain name for Route 53 configuration"
}

variable "db_password" {
  type        = string
  description = "Password for RDS database"
  sensitive   = true
}

# Rest of networking resources remain unchanged except for security groups
resource "aws_vpc" "wordpress_vpc" {
  # Previous configuration remains the same
}

# Modified security groups to address findings
resource "aws_security_group" "alb" {
  name        = "wordpress-alb-sg"
  description = "Security group for WordPress ALB"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "HTTPS from CloudFront only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [for ip in aws_cloudfront_distribution.wordpress.domain_name : "${ip}/32"]
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

# Modified RDS instance to address encryption and backup findings
resource "aws_db_instance" "wordpress" {
  identifier           = "wordpress-db"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  name                = "wordpress"
  username            = "wordpress"
  password            = var.db_password
  skip_final_snapshot = false
  
  # Added security configurations
  storage_encrypted               = true
  backup_retention_period        = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
  }
}

# Modified ALB configuration to address findings
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
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.wordpress.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

# Added WAF for ALB
resource "aws_wafregional_web_acl_association" "wordpress" {
  resource_arn = aws_lb.wordpress.arn
  web_acl_id   = aws_wafregional_web_acl.wordpress.id
}

# Modified CloudFront distribution to use custom SSL certificate
resource "aws_cloudfront_distribution" "wordpress" {
  # Previous configuration remains the same except for viewer certificate
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.wordpress.arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  # Added logging configuration
  logging_config {
    include_cookies = false
    bucket         = aws_s3_bucket.logs.bucket_domain_name
    prefix         = "cloudfront/"
  }

  web_acl_id = aws_waf_web_acl.wordpress_cloudfront.id
}

# Added outputs with descriptions
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}

output "rds_endpoint" {
  description = "Endpoint URL of the RDS instance"
  value       = aws_db_instance.wordpress.endpoint
}
