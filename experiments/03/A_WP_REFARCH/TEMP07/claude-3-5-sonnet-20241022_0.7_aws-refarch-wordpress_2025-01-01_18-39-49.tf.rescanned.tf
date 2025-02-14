
# Provider and terraform configuration
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
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "domain_name" {
  description = "Domain name for the WordPress site"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "wordpress"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "wordpress"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

# VPC Resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
    Project     = "wordpress"
  }
}

# Enable VPC Flow Logs
resource "aws_flow_log" "vpc_flow_log" {
  vpc_id          = aws_vpc.wordpress_vpc.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/wordpress-flow-logs"
  retention_in_days = 30
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name        = "wordpress-public-${count.index + 1}"
    Environment = var.environment
  }
}

# Security Groups with descriptions for all rules
resource "aws_security_group" "alb" {
  name        = "wordpress-alb-sg"
  description = "Security group for WordPress ALB"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow HTTPS inbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

# RDS Instance with enhanced security
resource "aws_db_instance" "wordpress" {
  identifier                          = "wordpress-db"
  engine                             = "mysql"
  engine_version                     = "8.0"
  instance_class                     = "db.t3.small"
  allocated_storage                  = 20
  storage_type                       = "gp2"
  storage_encrypted                  = true
  db_name                           = var.db_name
  username                          = var.db_username
  password                          = var.db_password
  skip_final_snapshot               = true
  iam_database_authentication_enabled = true
  vpc_security_group_ids            = [aws_security_group.rds.id]
  db_subnet_group_name              = aws_db_subnet_group.wordpress.name
  backup_retention_period           = 7
  multi_az                         = true
  enabled_cloudwatch_logs_exports   = ["error", "general", "slowquery"]

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
  }
}

# S3 Bucket with versioning and logging
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${var.environment}"

  tags = {
    Name        = "wordpress-assets"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "wordpress_assets" {
  bucket = aws_s3_bucket.wordpress_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "wordpress_assets" {
  bucket        = aws_s3_bucket.wordpress_assets.id
  target_bucket = aws_s3_bucket.wordpress_assets.id
  target_prefix = "access-logs/"
}

# Application Load Balancer with WAF and deletion protection
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

# WAF Web ACL
resource "aws_wafv2_web_acl" "wordpress" {
  name        = "wordpress-waf"
  description = "WAF for WordPress ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Add your WAF rules here
}

resource "aws_wafregional_web_acl_association" "wordpress" {
  resource_arn = aws_lb.wordpress.arn
  web_acl_id   = aws_wafv2_web_acl.wordpress.id
}

# Shield Advanced Protection
resource "aws_shield_protection" "wordpress_alb" {
  name         = "wordpress-alb-shield"
  resource_arn = aws_lb.wordpress.arn
}

# Outputs with descriptions
output "alb_dns_name" {
  description = "The DNS name of the application load balancer"
  value       = aws_lb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS database"
  value       = aws_db_instance.wordpress.endpoint
}
