
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

# Variables
variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources"
  default     = "us-west-2"
}

variable "project" {
  type        = string
  description = "Project name used for resource naming"
  default     = "wordpress"
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

variable "azs" {
  type        = list(string)
  description = "Availability zones to use"
  default     = ["us-west-2a", "us-west-2b"]
}

variable "public_subnets" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "db_name" {
  type        = string
  description = "Name of the RDS database"
  default     = "wordpress"
}

variable "db_user" {
  type        = string
  description = "Username for RDS database"
  default     = "wordpress"
}

variable "db_password" {
  type        = string
  description = "Password for RDS database"
  sensitive   = true
}

variable "domain_name" {
  type        = string
  description = "Domain name for the WordPress site"
  default     = "example.com"
}

# Enable IAM Access Analyzer
resource "aws_accessanalyzer_analyzer" "default" {
  analyzer_name = "${var.project}-analyzer"
  type          = "ACCOUNT"
  
  tags = {
    Name        = "${var.project}-analyzer"
    Environment = var.environment
  }
}

# VPC Flow Logs
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/${var.project}-flow-logs"
  retention_in_days = 30
  
  tags = {
    Name        = "${var.project}-flow-logs"
    Environment = var.environment
  }
}

resource "aws_iam_role" "flow_log" {
  name = "${var.project}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

# Remaining resources from original configuration...
# Only showing modified resources below

resource "aws_db_instance" "wordpress" {
  identifier                  = "${var.project}-db"
  allocated_storage          = 20
  storage_type              = "gp2"
  engine                    = "mysql"
  engine_version            = "8.0"
  instance_class            = "db.t3.micro"
  db_name                   = var.db_name
  username                  = var.db_user
  password                  = var.db_password
  skip_final_snapshot      = true
  storage_encrypted        = true
  backup_retention_period  = 7
  multi_az                 = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  vpc_security_group_ids   = [aws_security_group.rds.id]
  db_subnet_group_name     = aws_db_subnet_group.main.name

  tags = {
    Name        = "${var.project}-db"
    Environment = var.environment
  }
}

resource "aws_lb" "wordpress" {
  name                       = "${var.project}-alb"
  internal                   = false
  load_balancer_type        = "application"
  security_groups           = [aws_security_group.alb.id]
  subnets                   = aws_subnet.public[*].id
  enable_deletion_protection = true
  drop_invalid_header_fields = true

  tags = {
    Name        = "${var.project}-alb"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "wordpress" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_lb_listener" "redirect" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Shield Advanced protection
resource "aws_shield_protection" "alb" {
  name         = "${var.project}-alb-shield"
  resource_arn = aws_lb.wordpress.arn
}

resource "aws_shield_protection" "cloudfront" {
  name         = "${var.project}-cloudfront-shield"
  resource_arn = aws_cloudfront_distribution.wordpress.arn
}

# WAF Web ACL
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project}-web-acl"
  description = "Web ACL for WordPress"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Add rules as needed
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.wordpress.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
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
  description = "Endpoint of the RDS database"
  value       = aws_db_instance.wordpress.endpoint
}
