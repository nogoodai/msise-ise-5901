terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }

  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  type        = list(string)
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into bastion host"
  default     = "0.0.0.0/0"
  type        = string
}

variable "db_username" {
  description = "Username for the RDS database"
  default     = "admin"
  type        = string
}

variable "db_password" {
  description = "Password for the RDS database"
  type        = string
  sensitive   = true
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
  type        = string
}

variable "environment" {
  description = "Environment tag"
  default     = "production"
  type        = string
}

# VPC and Networking Resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "wordpress-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  description = "Security group for web servers."
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from anywhere"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "wordpress-web-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  description = "Security group for database servers."
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description     = "Allow MySQL access from web security group"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "wordpress-db-sg"
    Environment = var.environment
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix        = "wordpress-lc-"
  image_id           = var.ami_id
  instance_type      = var.instance_type
  security_groups    = [aws_security_group.web_sg.id]
  user_data          = base64encode(file("user_data.sh"))
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.private[*].id

  tag {
    key                 = "Name"
    value               = "wordpress-instance"
    propagate_at_launch = true
  }
  tags = {
    Environment = var.environment
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage            = 20
  engine                       = "mysql"
  instance_class               = "db.t2.small"
  name                         = "wordpressdb"
  username                     = var.db_username
  password                     = var.db_password
  vpc_security_group_ids       = [aws_security_group.db_sg.id]
  multi_az                     = true
  skip_final_snapshot          = true
  storage_encrypted            = true
  backup_retention_period      = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["error", "general", "slowquery", "audit"]
  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
  }
}

# ELB Configuration
resource "aws_lb" "wordpress_alb" {
  name                        = "wordpress-alb"
  internal                    = false
  load_balancer_type          = "application"
  security_groups             = [aws_security_group.web_sg.id]
  subnets                     = aws_subnet.public[*].id
  enable_deletion_protection  = true
  drop_invalid_header_fields  = true
  tags = {
    Name        = "wordpress-alb"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "redirect"
    redirect {
      protocol = "HTTPS"
      port     = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = {
    Name        = "wordpress-tg"
    Environment = var.environment
  }
}

resource "aws_lb_target_group_attachment" "asg" {
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_autoscaling_group.wordpress_asg.id
  port             = 80
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"
  }

  enabled = true

  default_cache_behavior {
    target_origin_id       = "wordpress-alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2019"
  }

  logging_config {
    bucket = aws_s3_bucket.wordpress_assets.bucket
    include_cookies = false
    prefix          = "cloudfront-logs/"
  }
  tags = {
    Name        = "wordpress-cf"
    Environment = var.environment
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_string.random_id.result}"
  acl    = "private"
  logging {
    target_bucket = aws_s3_bucket.wordpress_assets.bucket
    target_prefix = "s3-access-logs/"
  }
  versioning {
    enabled = true
  }
  tags = {
    Name        = "wordpress-assets"
    Environment = var.environment
  }
}

resource "random_string" "random_id" {
  length  = 8
  special = false
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
  tags = {
    Name        = "wordpress-zone"
    Environment = var.environment
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "wordpress"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "The ID of the VPC"
}

output "alb_dns_name" {
  value       = aws_lb.wordpress_alb.dns_name
  description = "The DNS name of the Application Load Balancer"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
  description = "The domain name of the CloudFront Distribution"
}
