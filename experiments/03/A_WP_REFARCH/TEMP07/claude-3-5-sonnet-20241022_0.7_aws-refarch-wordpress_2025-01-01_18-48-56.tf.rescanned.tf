
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
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "domain_name" {
  type        = string
  description = "Domain name for Route 53 and SSL certificate"
}

variable "db_password" {
  type        = string
  description = "Password for RDS database"
  sensitive   = true
}

# VPC Flow Logs
resource "aws_flow_log" "vpc_flow_log" {
  vpc_id          = aws_vpc.wordpress_vpc.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_log_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
}

resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name              = "/aws/vpc/wordpress-flow-logs"
  retention_in_days = 30
  
  tags = {
    Name        = "wordpress-vpc-flow-logs"
    Environment = var.environment
  }
}

# Network Firewall
resource "aws_networkfirewall_firewall" "wordpress" {
  name                = "wordpress-firewall"
  vpc_id              = aws_vpc.wordpress_vpc.id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.wordpress.arn
  
  subnet_mapping {
    subnet_id = aws_subnet.private[0].id
  }

  tags = {
    Name        = "wordpress-firewall"
    Environment = var.environment
  }
}

resource "aws_networkfirewall_firewall_policy" "wordpress" {
  name = "wordpress-firewall-policy"
  
  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
  }
}

# RDS Instance with enhanced security
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

# Application Load Balancer with enhanced security
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

# Security group rules with descriptions
resource "aws_security_group" "alb" {
  name        = "wordpress-alb-sg"
  description = "Security group for WordPress ALB"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow HTTPS inbound traffic"
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

# Enable WAF for ALB
resource "aws_wafregional_web_acl_association" "alb" {
  resource_arn = aws_lb.wordpress.arn
  web_acl_id   = aws_wafregional_web_acl.wordpress.id
}

resource "aws_wafregional_web_acl" "wordpress" {
  name        = "wordpress-waf-acl"
  metric_name = "WordPressWAFACL"
  
  default_action {
    type = "ALLOW"
  }
}

# Enable Shield Advanced protection
resource "aws_shield_protection" "alb" {
  name         = "wordpress-alb-shield"
  resource_arn = aws_lb.wordpress.arn
}

resource "aws_shield_protection" "cloudfront" {
  name         = "wordpress-cloudfront-shield"
  resource_arn = aws_cloudfront_distribution.wordpress.arn
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
  description = "Endpoint for the RDS database"
  value       = aws_db_instance.wordpress.endpoint
  sensitive   = true
}
