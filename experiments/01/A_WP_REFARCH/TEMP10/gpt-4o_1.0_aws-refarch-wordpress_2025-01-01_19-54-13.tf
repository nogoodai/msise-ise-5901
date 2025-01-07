terraform {
  required_providers {
    aws = "= 5.1.0"
  }

  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "admin_ssh_cidr" {
  description = "CIDR block for SSH administrative access"
  default     = "0.0.0.0/0"
}

variable "wordpress_instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.small"
}

variable "wordpress_key_name" {
  description = "SSH key name for EC2 instances"
}

variable "domain_name" {
  description = "Domain name for Route 53"
}

# VPC and Networking

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public" {
  count                  = 2
  vpc_id                 = aws_vpc.wordpress_vpc.id
  cidr_block             = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone      = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "wordpress-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count                  = 2
  vpc_id                 = aws_vpc.wordpress_vpc.id
  cidr_block             = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone      = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "wordpress-private-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "wordpress-public-rt"
  }
}

resource "aws_route_table_association" "public_rt_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Security Groups

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ssh_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress-web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress-db-sg"
  }
}

# EC2 Instances for WordPress

resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix   = "wordpress-lc-"
  image_id      = data.aws_ami.latest_amazon_linux.id
  instance_type = var.wordpress_instance_type
  key_name      = var.wordpress_key_name
  security_groups = [
    aws_security_group.web_sg.id
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 2
  vpc_zone_identifier  = aws_subnet.public[*].id
  launch_configuration = aws_launch_configuration.wordpress_lc.id

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

# RDS Instance for WordPress Database

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = random_password.db_password.result
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot = true
  multi_az            = true

  tags = {
    Name = "wordpress-db"
  }
}

# Elastic Load Balancer

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "wordpress-alb"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy = "ELBSecurityPolicy-2016-08"
  certificate_arn = "arn:aws:acm:your-certificate-arn"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
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
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

# CloudFront Distribution

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

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

    default_ttl = 3600
    min_ttl     = 0
    max_ttl     = 86400
  }

  viewer_certificate {
    acm_certificate_arn            = "arn:aws:acm:your-certificate-arn"
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2019"
  }
}

# S3 Bucket for Static Assets

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets"

  tags = {
    Name        = "wordpress-static-assets"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Route 53 DNS Configuration

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

# Outputs

output "wordpress_alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}
