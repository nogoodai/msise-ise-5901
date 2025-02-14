
# Provider and required provider configuration remain unchanged
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

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "domain_name" {
  type        = string
  description = "Domain name for Route 53"
}

variable "db_name" {
  type        = string
  description = "Name of the RDS database"
  default     = "wordpress"
}

variable "db_user" {
  type        = string
  description = "Username for RDS database"
  default     = "admin"
}

variable "db_password" {
  type        = string
  description = "Password for RDS database"
  sensitive   = true
}

# Rest of the resources remain the same until RDS instance

# RDS Instance with added security configurations
resource "aws_db_instance" "wordpress" {
  identifier           = "wordpress-db"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  db_name             = var.db_name
  username            = var.db_user
  password            = var.db_password
  skip_final_snapshot = true

  # Added security configurations
  storage_encrypted                  = true
  iam_database_authentication_enabled = true
  backup_retention_period            = 7
  enabled_cloudwatch_logs_exports    = ["audit", "error", "general", "slowquery"]

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress.name

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
  }
}

# Application Load Balancer with added security configurations
resource "aws_lb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = aws_subnet.public[*].id

  enable_deletion_protection = true
  drop_invalid_header_fields = true

  tags = {
    Name        = "wordpress-alb"
    Environment = var.environment
  }
}

# ALB Listener modified to use HTTPS
resource "aws_lb_listener" "wordpress" {
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

# Add WAF Web ACL
resource "aws_wafv2_web_acl" "wordpress" {
  name        = "wordpress-waf"
  description = "WAF Web ACL for WordPress"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = "WordPressWafMetric"
    sampled_requests_enabled  = true
  }
}

# Associate WAF with ALB
resource "aws_wafregional_web_acl_association" "wordpress" {
  resource_arn = aws_lb.wordpress.arn
  web_acl_id   = aws_wafv2_web_acl.wordpress.id
}

# Enable VPC Flow Logs
resource "aws_flow_log" "wordpress" {
  log_destination      = aws_cloudwatch_log_group.flow_log.arn
  log_destination_type = "cloud-watch-logs"
  traffic_type        = "ALL"
  vpc_id              = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-vpc-flow-log"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/wordpress-flow-logs"
  retention_in_days = 30

  tags = {
    Name        = "wordpress-vpc-flow-log-group"
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
  description = "Endpoint of the RDS instance"
  value       = aws_db_instance.wordpress.endpoint
}
