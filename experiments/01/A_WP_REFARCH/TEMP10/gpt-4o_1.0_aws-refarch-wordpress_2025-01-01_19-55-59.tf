terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

# Provider Configuration
provider "aws" {
  region = var.aws_region
}

# Variables
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

variable "allowed_ssh_ips" {
  description = "List of IPs allowed for SSH access"
  default     = ["0.0.0.0/0"]
}

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets
resource "aws_subnet" "public_subnet" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "private-subnet-${count.index}"
  }
}

# Internet Gateway and Routing
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  count       = length(aws_subnet.public_subnet)
  subnet_id   = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WebServerSG"
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
    Name = "DatabaseSG"
  }
}

# RDS Instance
resource "aws_db_instance" "wp_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpress"
  username             = "admin"
  password             = "admin123"
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az             = true
  skip_final_snapshot  = true
  publicly_accessible  = false
  tags = {
    Name = "WordPressDB"
  }
}

# Load Balancer
resource "aws_lb" "web_lb" {
  name               = "wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public_subnet[*].id
  
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_lb_target_group" "web_target_group" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path               = "/"
    interval           = 30
    timeout            = 5
    healthy_threshold  = 5
    unhealthy_threshold = 3
    matcher            = "200"
  }

  tags = {
    Name = "WordPressTG"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_target_group.arn
  }
}

# EC2 Instances and Auto Scaling
resource "aws_launch_configuration" "web_launch_config" {
  name          = "wordpress-launch-config"
  image_id      = "ami-0c55b159cbfafe1f0" # Example AMI, please replace
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd php php-mysqlnd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_asg" {
  launch_configuration = aws_launch_configuration.web_launch_config.name
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  vpc_zone_identifier  = aws_subnet.public_subnet[*].id

  target_group_arns = [aws_lb_target_group.web_target_group.arn]
  
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    }
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wp_distribution" {
  origin {
    domain_name = aws_lb.web_lb.dns_name
    origin_id   = "ALBWordPress"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "ALBWordPress"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
  
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "WordPressCDN"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "static_assets" {
  bucket = "wordpress-static-assets-${random_id.bucket_suffix.hex}"
  acl    = "public-read"

  tags = {
    Name = "WordPressStaticAssets"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wp_zone" {
  name = "example.com" # Replace with your domain
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wp_zone.zone_id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wp_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.wp_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "db_endpoint" {
  value = aws_db_instance.wp_db.endpoint
}

output "alb_dns_name" {
  value = aws_lb.web_lb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wp_distribution.domain_name
}
