terraform {
  required_providers {
    aws = ">= 5.1.0"
  }

  required_version = ">= 0.12"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  default     = "10.0.2.0/24"
}

variable "availability_zones" {
  description = "List of availability zones."
  default     = ["us-west-2a", "us-west-2b"]
}

variable "admin_ip" {
  description = "IP address for SSH access."
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Name of the SSH key pair."
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "WordPressPublicSubnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zones[0]

  tags = {
    Name = "WordPressPrivateSubnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server" {
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
    cidr_blocks = [var.admin_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressWebServerSG"
  }
}

resource "aws_security_group" "db" {
  vpc_id = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressDBSG"
  }
}

resource "aws_db_instance" "wordpress" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.db.id]

  multi_az            = true
  
  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_elb" "wordpress" {
  name               = "wordpress-elb"
  availability_zones = var.availability_zones
  security_groups    = [aws_security_group.web_server.id]
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
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "WordPressELB"
  }
}

resource "aws_autoscaling_group" "wordpress" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.private_subnet.id]
  launch_configuration = aws_launch_configuration.wordpress.id
  
  tags = [{
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-launch"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_server.id]
  key_name      = var.key_name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php mysql-client
              systemctl start httpd
              systemctl enable httpd
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  owners = ["amazon"]
}

resource "aws_s3_bucket" "wordpress" {
  bucket = "wordpress-static-assets"

  acl = "public-read"

  tags = {
    Name = "WordPressS3Bucket"
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress.bucket_regional_domain_name
    origin_id   = "s3-wordpress"
  }

  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-wordpress"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "WordPressCloudFront"
  }
}

resource "aws_route53_zone" "main" {
  name = "example.com"

  tags = {
    Name = "WordPressRoute53Zone"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "elb_dns_name" {
  value = aws_elb.wordpress.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}
