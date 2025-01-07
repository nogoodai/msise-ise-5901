terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  default = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "project_tags" {
  default = {
    Project = "WordPress"
    Environment = "Production"
  }
}

# Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags       = merge(var.project_tags, { Name = "wordpress-vpc" })
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags   = merge(var.project_tags, { Name = "internet-gateway" })
}

resource "aws_subnet" "public_subnet" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags                    = merge(var.project_tags, { Name = "public-subnet-${count.index + 1}" })
}

resource "aws_subnet" "private_subnet" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags                    = merge(var.project_tags, { Name = "private-subnet-${count.index + 1}" })
}

data "aws_availability_zones" "available" {}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
  tags = merge(var.project_tags, { Name = "public-route-table" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH from specific IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_admin_ips]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.project_tags, { Name = "web-sg" })
}

variable "allowed_admin_ips" {
  description = "Allowed IPs for admin SSH access"
  default     = ["1.2.3.4/32"] # Default example. Adjust as needed.
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    description       = "Allow MySQL from web server"
    from_port         = 3306
    to_port           = 3306
    protocol          = "tcp"
    security_groups   = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.project_tags, { Name = "rds-sg" })
}

# RDS Instance
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpress"
  username             = "admin"
  password             = "securepassword"
  parameter_group_name = "default.mysql5.7"
  multi_az             = true
  skip_final_snapshot  = true

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.wordpress_subnet_group.name

  tags = merge(var.project_tags, { Name = "wordpress-db" })
}

resource "aws_db_subnet_group" "wordpress_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnet[*].id

  tags = merge(var.project_tags, { Name = "wordpress-db-subnet-group" })
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress_launch_config" {
  name           = "wordpress-launch-config"
  image_id       = data.aws_ami.latest_amazon_linux.id
  instance_type  = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  user_data = base64encode("#!/bin/bash\nsudo yum update -y\n")

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.project_tags, { Name = "wordpress-instance" })
}

data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_launch_config.id
  max_size             = 3
  min_size             = 1
  desired_capacity     = 2
  vpc_zone_identifier  = aws_subnet.public_subnet[*].id

  tag {
    key                 = "Name"
    value               = "WordPress-ASG"
    propagate_at_launch = true
  }

  tags = merge(var.project_tags, { Name = "wordpress-asg" })
}

# Elastic Load Balancer (ALB)
resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public_subnet[*].id

  tags = merge(var.project_tags, { Name = "wordpress-alb" })
}

resource "aws_lb_listener" "frontend_http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-targets"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path     = "/"
    interval = 30
    timeout  = 5
  }

  tags = merge(var.project_tags, { Name = "wordpress-target-group" })
}

resource "aws_lb_target_group_attachment" "asg_attachment" {
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_autoscaling_group.wordpress_asg.id
  port             = 80
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "static_assets" {
  bucket = "wordpress-static-assets-${random_id.bucket_id.hex}"

  tags = merge(var.project_tags, { Name = "wordpress-static-assets" })
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "match-viewer"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    compress = true
  }

  tags = merge(var.project_tags, { Name = "wordpress-cloudfront" })
}

# Route 53 DNS
resource "aws_route53_record" "wordpress_domain" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "cert" {
  domain_name = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

variable "route53_zone_id" {
  description = "The ID of the Route53 Zone to use"
}

variable "domain_name" {
  description = "The domain name for the WordPress site"
}
