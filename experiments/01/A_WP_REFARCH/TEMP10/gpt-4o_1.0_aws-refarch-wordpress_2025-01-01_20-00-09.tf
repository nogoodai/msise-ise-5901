terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "allowed_ssh_ips" {
  description = "IP addresses allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  default     = "ami-00000000"
}

variable "key_name" {
  description = "Key pair name for EC2 instances"
}

variable "alb_domain_name" {
  description = "Domain name for the ALB"
}

resource "aws_vpc" "wordpress" {
  cidr_block = var.vpc_cidr
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "WordPressVPC"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidr)
  cidr_block = element(var.public_subnet_cidr, count.index)
  vpc_id = aws_vpc.wordpress.id
  map_public_ip_on_launch = true

  tags = {
    Name = "wordpress-public-subnet-${count.index + 1}"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidr)
  cidr_block = element(var.private_subnet_cidr, count.index)
  vpc_id = aws_vpc.wordpress.id

  tags = {
    Name = "wordpress-private-subnet-${count.index + 1}"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress" {
  vpc_id = aws_vpc.wordpress.id

  tags = {
    Name = "WordPressInternetGateway"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress.id
  }

  tags = {
    Name = "WordPressPublicRouteTable"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidr)
  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web-sg" {
  name        = "WordPressWebSG"
  vpc_id      = aws_vpc.wordpress.id

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
    Name = "WordPressWebSG"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_security_group" "db-sg" {
  name   = "WordPressDBSG"
  vpc_id = aws_vpc.wordpress.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web-sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressDBSG"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_elb" "web" {
  name               = "wordpress-elb"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.web-sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }

  tags = {
    Name = "WordPressELB"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress" {
  launch_configuration = aws_launch_configuration.wordpress.id
  min_size             = 2
  max_size             = 5
  vpc_zone_identifier  = aws_subnet.private[*].id

  tags = [{
    key                 = "Name"
    value               = "WordPressAutoScalingGroup"
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-launch-configuration"
  image_id      = var.ami_id
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.web-sg.id,
  ]
  key_name      = var.key_name

  user_data = <<-EOF
              #!/bin/bash
              yum install -y httpd php php-mysql
              wget http://wordpress.org/latest.tar.gz
              tar -xzf latest.tar.gz
              rsync -avP wordpress/ /var/www/html/
              chown -R apache:apache /var/www/html/*
              systemctl enable httpd
              systemctl start httpd
              EOF
}

resource "aws_route53_zone" "wordpress" {
  name = var.alb_domain_name

  tags = {
    Name = "WordPressHostedZone"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_elb.web.dns_name
    zone_id                = aws_elb.web.zone_id
    evaluate_target_health = false
  }
}

resource "aws_rds_instance" "wordpress" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "wpadmin"
  password             = "admin123"
  parameter_group_name = "default.mysql5.7"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.db-sg.id]

  tags = {
    Name = "WordPressRDSInstance"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets"
  acl    = "private"

  tags = {
    Name = "WordPressS3Bucket"
    Environment = "Production"
    Project = "WordPress"
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.wordpress_assets.id

    s3_origin_config {
      origin_access_identity = "origin-access-identity/cloudfront/E127EXAMPLE51Z"
    }
  }

  enabled = true
  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.wordpress_assets.id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["HEAD", "GET", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  tags = {
    Name = "WordPressCloudFrontDistribution"
    Environment = "Production"
    Project = "WordPress"
  }
}

output "elb_dns_name" {
  value = aws_elb.web.dns_name
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.id
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress.zone_id
}
