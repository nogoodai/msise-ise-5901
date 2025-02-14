
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

# Variables with improved documentation and types
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
  description = "Domain name for Route53 and SSL certificate"
}

variable "db_password" {
  type        = string
  description = "Password for RDS database"
  sensitive   = true
}

# VPC and Networking
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

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "wordpress-public-${count.index + 1}"
    Environment = var.environment
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "wordpress-private-${count.index + 1}"
    Environment = var.environment
    Project     = "wordpress"
  }
}

# Security Groups with improved descriptions and restrictions
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
    Project     = "wordpress"
  }
}

resource "aws_security_group" "wordpress" {
  name        = "wordpress-ec2-sg"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-ec2-sg"
    Environment = var.environment
    Project     = "wordpress"
  }
}

# RDS with encryption and improved security
resource "aws_db_instance" "wordpress" {
  identifier           = "wordpress-db"
  allocated_storage    = 20
  storage_type        = "gp2"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  username            = "wordpress"
  password            = var.db_password
  skip_final_snapshot = true

  db_subnet_group_name   = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  multi_az               = true
  storage_encrypted      = true
  
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports    = ["error", "general", "slowquery"]

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
    Project     = "wordpress"
  }
}

# Application Load Balancer with improved security
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
    Project     = "wordpress"
  }
}

# CloudFront with WAF and improved security
resource "aws_wafv2_web_acl" "wordpress" {
  name        = "wordpress-waf"
  description = "WAF for WordPress"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Add WAF rules as needed
}

resource "aws_cloudfront_distribution" "wordpress" {
  enabled             = true
  default_root_object = "index.php"
  web_acl_id         = aws_wafv2_web_acl.wordpress.id

  origin {
    domain_name = aws_lb.wordpress.dns_name
    origin_id   = aws_lb.wordpress.name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_lb.wordpress.name
    viewer_protocol_policy = "redirect-to-https"
    min_ttl               = 0
    default_ttl           = 3600
    max_ttl               = 86400

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    minimum_protocol_version      = "TLSv1.2_2021"
    ssl_support_method           = "sni-only"
    acm_certificate_arn          = aws_acm_certificate.wordpress.arn
  }

  tags = {
    Name        = "wordpress-cdn"
    Environment = var.environment
    Project     = "wordpress"
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
  description = "Endpoint of the RDS database"
  value       = aws_db_instance.wordpress.endpoint
  sensitive   = true
}
