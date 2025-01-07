terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

variable "region" {
  description = "AWS region to deploy the resources"
  type        = string
  default     = "us-west-2"
}

variable "profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "default"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
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

variable "instance_type" {
  description = "EC2 instance type for WordPress"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "AMI ID for the WordPress instances"
  type        = string
}

variable "key_pair_name" {
  description = "SSH key pair name for EC2 instances"
  type        = string
}

variable "allowed_ssh_ips" {
  description = "Allowed IPs for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
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
    Name = "WordPressInternetGateway"
  }
}

resource "aws_subnet" "public" {
  for_each = toset(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = each.value
  map_public_ip_on_launch = true
  tags = {
    Name = "WordPressPublicSubnet-${each.value}"
  }
}

resource "aws_subnet" "private" {
  for_each = toset(var.private_subnet_cidrs)
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = each.value
  tags = {
    Name = "WordPressPrivateSubnet-${each.value}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  for_each          = aws_subnet.public
  subnet_id         = each.value.id
  route_table_id    = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WebServerSG"
  }

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
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "DatabaseSG"
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
}

resource "aws_instance" "bastion" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_pair_name
  subnet_id     = aws_subnet.public["10.0.1.0/24"].id
  associate_public_ip_address = true
  tags = {
    Name = "BastionHost"
  }

  security_groups = [aws_security_group.web_sg.name]
}

resource "aws_eip" "bastion_eip" {
  vpc = true
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress_efs" {
  tags = {
    Name = "WordPressEFS"
  }
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  for_each = aws_subnet.private
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id = each.value.id
}

resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix    = "wordpress-lc-"
  image_id       = var.ami_id
  instance_type  = var.instance_type
  key_name       = var.key_pair_name
  security_groups = [aws_security_group.web_sg.id]

  user_data = <<-EOT
              #!/bin/bash
              yum update -y
              # Install and configure WordPress
              EOT
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  vpc_zone_identifier  = aws_subnet.private[*].id
  tags = [
    {
      key                 = "Name"
      value               = "AutoScalingGroup"
      propagate_at_launch = true
    },
  ]
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
    ssl_certificate_id = "arn:aws:acm:<region>:<account_id>:certificate/<certificate-id>"
  }
}

resource "aws_db_instance" "wordpress_db" {
  identifier         = "wordpress-db"
  engine             = "mysql"
  instance_class     = "db.t2.small"
  multi_az           = true
  allocated_storage  = 20
  username           = "admin"
  password           = "password"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  name               = "wordpressdb"
  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-origin"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-origin"
    viewer_protocol_policy = "redirect-to-https"
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

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_id.hex}"
  acl    = "private"
  tags = {
    Name = "WordPressAssets"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
  tags = {
    Name = "WordPressHostedZone"
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id                = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cf" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn.example.com"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.wordpress_cf.domain_name]
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.wordpress_vpc.id
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_elb.wordpress_elb.dns_name
}

output "efs_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.wordpress_efs.id
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.wordpress_db.endpoint
}
