# Configure the AWS Provider
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables for user-configurable values
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "database_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment for the resources"
}

variable "project" {
  type        = string
  default     = "wordpress"
  description = "Project name for the resources"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "public-subnet-1"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name        = "public-subnet-2"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "private-subnet-1"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name        = "private-subnet-2"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security groups
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "wordpress-ec2-sg"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic from anywhere"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from anywhere"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow SSH traffic from within the VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "wordpress-ec2-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
    description     = "Allow MySQL traffic from WordPress EC2 instances"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "wordpress-rds-sg"
    Environment = var.environment
    Project     = var.project
  }
}

# EC2 instances
resource "aws_instance" "wordpress_ec2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private_subnet_1.id
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true
  tags = {
    Name        = "wordpress-ec2"
    Environment = var.environment
    Project     = var.project
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.database_instance_class
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  storage_encrypted    = true
  backup_retention_period = 12
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  iam_database_authentication_enabled = true
  tags = {
    Name        = "wordpress-rds"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = var.environment
    Project     = var.project
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_elb" {
  name               = "wordpress-elb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress_ec2_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  enable_deletion_protection = true
  drop_invalid_header_fields = true
  tags = {
    Name        = "wordpress-elb"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lb_listener" "wordpress_elb_listener" {
  load_balancer_arn = aws_lb.wordpress_elb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_elb_target_group.arn
  }
}

resource "aws_lb_target_group" "wordpress_elb_target_group" {
  name     = "wordpress-elb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-elb-target-group"
    Environment = var.environment
    Project     = var.project
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_ec2_asg" {
  name                = "wordpress-ec2-asg"
  max_size            = 3
  min_size            = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity        = 1
  launch_configuration      = aws_launch_configuration.wordpress_ec2_lc.name
  vpc_zone_identifier       = aws_subnet.private_subnet_1.id
  load_balancers = [aws_lb.wordpress_elb.name]
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-ec2-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_ec2_lc" {
  name          = "wordpress-ec2-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  user_data = "#!/bin/bash\nsudo apt-get update -y\nsudo apt-get install -y apache2\nsudo systemctl start apache2\nsudo systemctl enable apache2"
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront" {
  origin {
    domain_name = aws_lb.wordpress_elb.dns_name
    origin_id   = "S3Origin"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = ["example.com", "www.example.com"]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
  logging_config {
    bucket = aws_s3_bucket.wordpress_s3.id
    prefix = "cloudfront-logs/"
  }
  tags = {
    Name        = "wordpress-cloudfront"
    Environment = var.environment
    Project     = var.project
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.wordpress_s3_logs.id
    target_prefix = "/logs/"
  }
  tags = {
    Name        = "wordpress-s3-bucket"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket" "wordpress_s3_logs" {
  bucket = "wordpress-s3-logs"
  acl    = "log-delivery-write"
  tags = {
    Name        = "wordpress-s3-logs"
    Environment = var.environment
    Project     = var.project
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_route53" {
  name = "example.com"
  tags = {
    Name        = "example.com"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53.id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_elb.dns_name
    zone_id               = aws_lb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_query_log" "wordpress_route53_query_log" {
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.wordpress_route53_query_log_group.arn
  zone_id                  = aws_route53_zone.wordpress_route53.id
}

resource "aws_cloudwatch_log_group" "wordpress_route53_query_log_group" {
  name = "wordpress-route53-query-logs"
  retention_in_days = 30
  tags = {
    Name        = "wordpress-route53-query-logs"
    Environment = var.environment
    Project     = var.project
  }
}

output "wordpress_vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "The ID of the WordPress VPC"
}

output "wordpress_elb_dns_name" {
  value       = aws_lb.wordpress_elb.dns_name
  description = "The DNS name of the WordPress ELB"
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the WordPress RDS instance"
}

output "wordpress_cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.wordpress_cloudfront.id
  description = "The ID of the WordPress CloudFront distribution"
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_s3.bucket
  description = "The name of the WordPress S3 bucket"
}

output "wordpress_route53_zone_id" {
  value       = aws_route53_zone.wordpress_route53.id
  description = "The ID of the WordPress Route 53 zone"
}
