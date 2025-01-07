terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = "us-east-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ip" {
  description = "The list of CIDR blocks allowed to SSH"
  default     = ["0.0.0.0/0"]  # Modify as needed
}

variable "environment" {
  default = "production"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block       = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidr)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnet_cidr[count.index]
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "public-subnet-${count.index+1}"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidr)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnet_cidr[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "private-subnet-${count.index+1}"
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

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "public-route-table"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

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
    cidr_blocks = var.allowed_ip
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "web-server-sg"
    Environment = var.environment
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
    Name        = "db-sg"
    Environment = var.environment
  }
}

resource "aws_launch_configuration" "wordpress" {
  image_id          = "ami-0a313d6098716f372" # Amazon Linux 2 AMI
  instance_type     = "t2.micro"
  security_groups   = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  lifecycle {
    create_before_destroy = true
  }
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysqlnd
              systemctl start httpd
              systemctl enable httpd
              EOF
}

resource "aws_autoscaling_group" "wordpress_asg" {
  vpc_zone_identifier = aws_subnet.public[*].id
  launch_configuration = aws_launch_configuration.wordpress.id
  min_size = 1
  max_size = 3
  desired_capacity = 1

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-instance"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    }
  ]
}

resource "aws_elb" "wordpress_lb" {
  availability_zones = data.aws_availability_zones.available.names
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  listener {
    instance_port     = 443
    instance_protocol = "HTTP"
    lb_port           = 443
    lb_protocol       = "HTTPS"
  }
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  instances = aws_autoscaling_group.wordpress_asg.instances
  tags = {
    Name        = "wordpress-elb"
    Environment = var.environment
  }
}

resource "aws_rds_instance" "wordpress_db" {
  engine         = "mysql"
  instance_class = "db.t2.small"
  allocated_storage = 20
  name        = "wordpressdb"
  username    = "admin"
  password    = "password" // Replace with secure value
  multi_az    = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  tags = {
    Name        = "wordpress-rds"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${var.environment}"
  acl    = "public-read"

  tags = {
    Name        = "wordpress-assets"
    Environment = var.environment
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_elb.wordpress_lb.dns_name
    origin_id   = "wordpress-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_cache_behavior {
    allowed_methods    = ["GET", "HEAD"]
    cached_methods     = ["GET", "HEAD"]
    target_origin_id   = "wordpress-origin"
    viewer_protocol_policy = "redirect-to-https"
    min_ttl            = 0
    default_ttl        = 3600
    max_ttl            = 86400

    forwarded_values {
      query_string = false
      headers      = ["*"]
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
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "wordpress-cloudfront"
    Environment = var.environment
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com" // Replace with actual domain
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www.example.com" // Replace with actual subdomain
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_lb.dns_name
    zone_id                = aws_elb.wordpress_lb.zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

output "wordpress_lb_url" {
  value = aws_elb.wordpress_lb.dns_name
}

output "wordpress_db_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}

output "cloudfront_distribution_domain" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}
