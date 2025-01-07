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
  description = "AWS region to deploy resources"
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

variable "admin_ips" {
  description = "Admin IP range for SSH access"
  type        = list(string)
  default     = ["203.0.113.0/24"]
}

resource "aws_vpc" "wordpress" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress.id
  tags = {
    Name        = "WordPress-IGW"
    Environment = "production"
  }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name        = "WordPress-Public-Subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.wordpress.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPress-Private-Subnet-${count.index}"
    Environment = "production"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "WordPress-Public-Route-Table"
    Environment = "production"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress.id
  description = "Allow HTTP, HTTPS, and SSH access"
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
    cidr_blocks = var.admin_ips
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPress-Web-SG"
    Environment = "production"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress.id
  description = "Allow MySQL access from web server"
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
    Name        = "WordPress-DB-SG"
    Environment = "production"
  }
}

resource "aws_elb" "wordpress" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  listener {
    instance_port     = 443
    instance_protocol = "HTTPS"
    lb_port           = 443
    lb_protocol       = "HTTPS"
    ssl_certificate_id = var.ssl_certificate_arn
  }

  security_groups = [aws_security_group.web_sg.id]
  subnets         = aws_subnet.public[*].id

  tags = {
    Name        = "WordPress-ELB"
    Environment = "production"
  }
}

resource "aws_autoscaling_group" "web_asg" {
  launch_configuration = aws_launch_configuration.web_launch_config.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.public[*].id
  target_group_arns    = [aws_lb_target_group.wordpress.arn]

  tag {
    key                 = "Name"
    value               = "WordPress-Web-ASG"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "web_launch_config" {
  name          = "wordpress-launch-config"
  image_id      = data.aws_ami.latest_amazon_linux.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y wordpress php mysql-server
              EOF
}

resource "aws_rds_instance" "db" {
  allocated_storage    = 20
  engine               = "aurora"
  instance_class       = "db.t2.small"
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name        = "WordPress-RDS"
    Environment = "production"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${var.region}-${random_id.bucket_id.hex}"
  acl    = "private"
  tags = {
    Name        = "WordPress-Assets"
    Environment = "production"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-WORDPRESS-ASSETS"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-WORDPRESS-ASSETS"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  tags = {
    Name        = "WordPress-CloudFront"
    Environment = "production"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
  tags = {
    Environment = "production"
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "wordpress.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {}

data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress.id
}

output "elb_dns" {
  value = aws_elb.wordpress.dns_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.bucket
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_distribution.domain_name
}
