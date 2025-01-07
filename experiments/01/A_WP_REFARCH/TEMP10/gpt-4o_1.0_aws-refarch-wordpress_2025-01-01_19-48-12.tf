terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = "us-east-1"
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
  description = "Allowed IPs for SSH access"
  default     = ["0.0.0.0/0"]
}

variable "environment" {
  default = "production"
}

variable "project" {
  default = "wordpress-project"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public" {
  for_each = toset(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
  tags = {
    Name        = "wordpress-public-${cidrhost(each.value, 1)}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private" {
  for_each = toset(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = "us-east-1a"
  tags = {
    Name        = "wordpress-private-${cidrhost(each.value, 1)}"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "wordpress-public-rt"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route" "igw_route" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  name   = "web-server-sg"
  vpc_id = aws_vpc.main.id

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
    cidr_blocks = var.allowed_ssh_ips
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
    Project     = var.project
  }
}

resource "aws_elb" "wordpress" {
  name               = "wordpress-elb"
  subnets            = [for subnet in aws_subnet.public : subnet.id]
  security_groups    = [aws_security_group.web_sg.id]
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

  tags = {
    Name        = "wordpress-elb"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  availability_zones   = ["us-east-1a"]
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  force_delete         = true
  health_check_type    = "EC2"
  health_check_grace_period = 300

  launch_configuration = aws_launch_configuration.wordpress_lc.id

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
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

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-config"
  image_id      = "ami-12345678" # Replace with actual AMI
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd php mysql
              service httpd start
              chkconfig httpd on
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress_db" {
  instance_class         = "db.t2.small"
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "5.7"
  name                   = "wordpressdb"
  username               = "admin"
  password               = "password"
  parameter_group_name   = "default.mysql5.7"
  multi_az               = true
  storage_type           = "gp2"
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
    Project     = var.project
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-bucket"
  acl    = "private"

  tags = {
    Name        = "wordpress-assets"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "wordpress-s3-origin"
  }

  enabled = true

  default_cache_behavior {
    target_origin_id       = "wordpress-s3-origin"
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

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "wordpress-cf"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com" # Replace with actual domain

  tags = {
    Name        = "wordpress-zone"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cdn" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "cdn"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_cloudfront_distribution.wordpress_cf.domain_name]
}

output "ec2_instance_ids" {
  description = "EC2 instance IDs"
  value       = aws_autoscaling_group.wordpress_asg.id
}

output "db_endpoint" {
  description = "RDS Database Endpoint"
  value       = aws_db_instance.wordpress_db.endpoint
}

output "s3_bucket_name" {
  description = "S3 Bucket for WordPress static assets"
  value       = aws_s3_bucket.wordpress_assets.id
}

output "cloudfront_domain_name" {
  description = "CloudFront Distribution Domain Name"
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
}
