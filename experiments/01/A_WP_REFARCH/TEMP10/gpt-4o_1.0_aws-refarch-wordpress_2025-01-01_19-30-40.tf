terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "The AWS region to create resources in"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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

variable "allowed_ssh_ip" {
  description = "IP addresses allowed to SSH into the bastion host"
  default     = "0.0.0.0/0"
}

variable "db_engine" {
  description = "The database engine"
  default     = "aurora"
}

variable "db_instance_class" {
  description = "The database instance class"
  default     = "db.t2.small"
}

variable "db_name" {
  description = "Database name for WordPress"
  default     = "wordpress"
}

variable "db_username" {
  description = "The username for the database"
  default     = "admin"
}

variable "db_password" {
  description = "The password for the database"
  sensitive   = true
}

variable "alb_certificate_arn" {
  description = "ARN of the SSL certificate for ALB"
  default     = ""
}

variable "ssh_key_name" {
  description = "SSH key name for EC2 instances"
  default     = "my-keypair"
}

variable "project_name" {
  description = "The project name for tagging"
  default     = "WordPressProject"
}

variable "environment" {
  description = "The deployment environment"
  default     = "production"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "public" {
  for_each = toset(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = {
    Name        = "wordpress-public-subnet-${element(keys(var.public_subnet_cidrs), index(var.public_subnet_cidrs, each.value))}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private" {
  for_each = toset(var.private_subnet_cidrs)

  vpc_id      = aws_vpc.main.id
  cidr_block  = each.value

  tags = {
    Name        = "wordpress-private-subnet-${element(keys(var.private_subnet_cidrs), index(var.private_subnet_cidrs, each.value))}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "wordpress-public-route-table"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  for_each = toset(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from specific IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-web-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    description = "MySQL from Web SG"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wordpress-db-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Bastion Host
resource "aws_instance" "bastion" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  key_name      = var.ssh_key_name
  subnet_id     = aws_subnet.public["10.0.1.0/24"].id

  security_groups = [aws_security_group.web_sg.id]

  tags = {
    Name        = "wordpress-bastion-host"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id

  tags = {
    Name        = "wordpress-bastion-eip"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EFS
resource "aws_efs_file_system" "wordpress" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name        = "wordpress-efs"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_efs_mount_target" "wordpress" {
  for_each = toset(union(var.public_subnet_cidrs, var.private_subnet_cidrs))

  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = element(aws_subnet.private[*].id, index(var.private_subnet_cidrs, each.key))

  security_groups = [aws_security_group.web_sg.id]
}

# RDS
resource "aws_db_instance" "wordpress" {
  allocated_storage   = 20
  engine              = var.db_engine
  instance_class      = var.db_instance_class
  name                = var.db_name
  username            = var.db_username
  password            = var.db_password
  multi_az            = true
  skip_final_snapshot = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name        = "wordpress-rds"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Elasticache
resource "aws_elasticache_cluster" "wordpress" {
  engine        = "redis"
  node_type     = "cache.t2.micro"
  num_cache_nodes = 1
  parameter_group_name = "default.redis3.2"

  subnet_group_name = aws_elasticache_subnet_group.wordpress.id

  security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name        = "wordpress-elasticache"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_elasticache_subnet_group" "wordpress" {
  name       = "wordpress-elasticache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

# Load Balancer
resource "aws_lb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "wordpress-alb"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type = "forward"

    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
  }

  tags = {
    Name        = "wordpress-target-group"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Auto Scaling Group
resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  key_name      = var.ssh_key_name
  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y httpd php php-mysqlnd
                chkconfig httpd on
                service httpd start
                echo "<?php phpinfo(); ?>" > /var/www/html/index.php
                EOF
}

resource "aws_autoscaling_group" "wordpress" {
  desired_capacity     = 1
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private[*].id
  launch_configuration = aws_launch_configuration.wordpress.id

  target_group_arns = [aws_lb_target_group.wordpress.arn]

  tag {
    key                 = "Name"
    value               = "wordpress-asg-instance"
    propagate_at_launch = true
  }
}

# CloudFront
resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_lb.wordpress.dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "match-viewer"
    }
  }

  enabled = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"

    forwarded_values {
      query_string = false

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.alb_certificate_arn
    ssl_support_method  = "sni-only"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${var.environment}"

  tags = {
    Name        = "wordpress-assets-bucket"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Route 53
data "aws_route53_zone" "selected" {
  name         = "example.com"
  private_zone = false
}

resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress.dns_name
    zone_id                = aws_lb.wordpress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cdn" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "cdn"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.wordpress.domain_name]
}

# Outputs
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.wordpress.dns_name
}

output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_db_instance.wordpress.endpoint
}

output "cloudfront_distribution_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}
