terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH into bastion and web servers."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type for WordPress and Bastion hosts."
  default     = "t2.micro"
}

variable "key_name" {
  description = "Name of the SSH key pair."
  default     = "my-key-pair"
}

variable "db_instance_class" {
  description = "Instance class for RDS."
  default     = "db.t2.small"
}

variable "cloudfront_origin" {
  description = "Origin for CloudFront distribution."
  default     = "s3"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "PublicRouteTable"
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
    cidr_blocks = var.allowed_ssh_cidrs
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

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = aws_subnet.public[0].id
  associate_public_ip_address = true

  security_groups = [aws_security_group.web_sg.name]

  tags = {
    Name = "BastionHost"
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  vpc      = true
}

resource "aws_efs_file_system" "wordpress_efs" {
  tags = {
    Name = "WordPressEFS"
  }

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mt" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [
    aws_security_group.web_sg.id,
  ]
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql5.7"
  multi_az             = true
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.public[*].id
  health_check_type    = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  image_id          = data.aws_ami.amazon_linux.id
  instance_type     = var.instance_type
  security_groups   = [aws_security_group.web_sg.id]
  key_name          = var.key_name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
              yum install -y httpd mariadb-server
              systemctl start httpd
              systemctl enable httpd
              echo "<?php phpinfo(); ?>" > /var/www/html/phpinfo.php
              EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "wordpress_elb" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names
  security_groups    = [aws_security_group.web_sg.id]

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
    ssl_certificate_id = "arn:aws:acm:region:account:certificate/certificate-id"
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

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_string.suffix.result}"
  acl    = "private"

  tags = {
    Name = "WordPressAssets"
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-wordpress-assets"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for WordPress"
  default_cache_behavior {
    target_origin_id       = "S3-wordpress-assets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  tags = {
    Name = "WordPressCDN"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress.id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cdn" {
  zone_id = aws_route53_zone.wordpress.id
  name    = "cdn.example.com"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.wordpress_cdn.domain_name]
}

data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.wordpress_vpc.id
}

output "elb_dns_name" {
  description = "The DNS name of the ELB"
  value       = aws_elb.wordpress_elb.dns_name
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.wordpress_assets.bucket
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_rds_instance.wordpress_db.endpoint
}
