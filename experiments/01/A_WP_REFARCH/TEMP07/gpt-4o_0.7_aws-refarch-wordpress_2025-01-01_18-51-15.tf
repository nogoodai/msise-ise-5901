terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "allowed_ssh_ips" {
  description = "List of IPs allowed to SSH into bastion and web servers."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "application_name" {
  description = "Name of the application."
  default     = "WordPress"
}

variable "environment" {
  description = "Environment name."
  default     = "production"
}

# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "${var.application_name}-vpc"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.application_name}-igw"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "${var.application_name}-public-subnet-${count.index}"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "${var.application_name}-private-subnet-${count.index}"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "${var.application_name}-public-rt"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.application_name}-web-sg"
  vpc_id      = aws_vpc.wordpress_vpc.id
  description = "Allow web traffic and SSH from allowed IPs."

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = var.allowed_ssh_ips
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.application_name}-web-sg"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_security_group" "db_sg" {
  name        = "${var.application_name}-db-sg"
  vpc_id      = aws_vpc.wordpress_vpc.id
  description = "Allow MySQL access from web servers."

  ingress {
    description      = "MySQL"
    from_port        = 3306
    to_port          = 3306
    protocol         = "tcp"
    security_groups  = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.application_name}-db-sg"
    Environment = var.environment
    Project     = var.application_name
  }
}

# EC2 Instances for WordPress
resource "aws_launch_configuration" "wordpress" {
  name          = "${var.application_name}-launch-config"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php mysql
              service httpd start
              chkconfig httpd on
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.public.*.id

  tags = [
    {
      key                 = "Name"
      value               = "${var.application_name}-web"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.application_name
      propagate_at_launch = true
    }
  ]
}

# RDS Instance for WordPress
resource "aws_db_instance" "wordpress_db" {
  identifier              = "${var.application_name}-db"
  engine                  = "mysql"
  instance_class          = "db.t2.small"
  allocated_storage       = 20
  db_name                 = "wordpress"
  username                = "admin"
  password                = "password"
  multi_az                = true
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name

  tags = {
    Name        = "${var.application_name}-db"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.application_name}-db-subnet-group"
  subnet_ids = aws_subnet.private.*.id

  tags = {
    Name        = "${var.application_name}-db-subnet-group"
    Environment = var.environment
    Project     = var.application_name
  }
}

# Elastic Load Balancer
resource "aws_lb" "wordpress_alb" {
  name               = "${var.application_name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public.*.id

  tags = {
    Name        = "${var.application_name}-alb"
    Environment = var.environment
    Project     = var.application_name
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

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "${var.application_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "${var.application_name}-tg"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_lb_listener_rule" "default" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }

  condition {
    field  = "path-pattern"
    values = ["*"]
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.static_assets.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${var.application_name}"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    target_origin_id       = "S3-${aws_s3_bucket.static_assets.id}"
    viewer_protocol_policy = "redirect-to-https"

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

  tags = {
    Name        = "${var.application_name}-cf"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "${var.application_name} access identity"
}

resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.application_name}-assets"

  tags = {
    Name        = "${var.application_name}-assets"
    Environment = var.environment
    Project     = var.application_name
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "zone" {
  name = "example.com"

  tags = {
    Name        = "${var.application_name}-zone"
    Environment = var.environment
    Project     = var.application_name
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.zone.id
  name    = "www.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cdn" {
  zone_id = aws_route53_zone.zone.id
  name    = "cdn.example.com"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.wordpress.domain_name]
}

# Outputs
output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}
