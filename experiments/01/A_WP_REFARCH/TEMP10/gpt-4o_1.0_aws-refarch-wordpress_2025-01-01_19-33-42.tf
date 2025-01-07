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
  description = "The AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "Allowed IPs for SSH access"
  default     = ["0.0.0.0/0"] # Adjust for secure access
}

variable "key_pair_name" {
  description = "Name of the AWS EC2 Key Pair"
  default     = "my-key-pair"
}

variable "wordpress_instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.small"
}

variable "ami_id" {
  description = "AMI ID for the web and bastion EC2 instances"
  default     = "ami-12345678" # Example default, update with actual AMI IDs
}

variable "alb_certificate_arn" {
  description = "ARN of the ACM certificate for the ALB"
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
  count                  = length(var.public_subnet_cidrs)
  vpc_id                 = aws_vpc.wordpress_vpc.id
  cidr_block             = element(var.public_subnet_cidrs, count.index)
  availability_zone      = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count              = length(var.private_subnet_cidrs)
  vpc_id             = aws_vpc.wordpress_vpc.id
  cidr_block         = element(var.private_subnet_cidrs, count.index)
  availability_zone  = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PrivateSubnet-${count.index}"
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

resource "aws_route_table_association" "public_association" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_server_sg" {
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

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "RDSSG"
  }
}

resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
  }
  tags = {
    Name = "BastionSG"
  }
}

resource "aws_instance" "bastion_host" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  security_groups             = [aws_security_group.bastion_sg.name]
  tags = {
    Name = "BastionHost"
  }
}

resource "aws_elb" "wordpress_alb" {
  name               = "wordpress-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_server_sg.id]
  subnets            = aws_subnet.public[*].id

  listener {
    port     = 80
    protocol = "HTTP"

    default_action {
      type             = "forward"
      target_group_arn = aws_lb_target_group.wordpress_tg.arn
    }
  }

  listener {
    port     = 443
    protocol = "HTTPS"
    ssl_policy = "ELBSecurityPolicy-2020-06"
    certificate_arn = var.alb_certificate_arn

    default_action {
      type             = "forward"
      target_group_arn = aws_lb_target_group.wordpress_tg.arn
    }
  }

  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.private[*].id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressInstance"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-configuration"
  image_id      = var.ami_id
  instance_type = var.wordpress_instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  user_data     = <<-EOF
                #!/bin/bash
                # Install WordPress
                yum update -y
                yum install -y httpd
                systemctl start httpd
                systemctl enable httpd
                EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress"
  protocol = "HTTP"
  port     = 80
  vpc_id   = aws_vpc.wordpress_vpc.id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = {
    Name = "WordPressTargetGroup"
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  instance_class       = var.rds_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  parameter_group_name = "default.mysql8.0"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  tags = {
    Name = "WordPressRDS"
  }
}

resource "aws_s3_bucket" "static_assets" {
  bucket = "wordpress-static-assets-1234"
  acl    = "public-read"
  tags = {
    Name = "WordPressStaticAssets"
  }
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_elb.wordpress_alb.dns_name
    origin_id   = "wordpress-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CDN"
  default_root_object = "index.html"
  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-origin"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  tags = {
    Name = "WordPressDistribution"
  }
}

resource "aws_route53_zone" "wordpress_dns" {
  name = "example.com"
  tags = {
    Name = "WordPressHostedZone"
  }
}

resource "aws_route53_record" "wordpress_alb_record" {
  zone_id = aws_route53_zone.wordpress_dns.zone_id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_alb.dns_name
    zone_id                = aws_elb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.wordpress_vpc.id
}

output "bastion_host_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion_host.public_ip
}

output "elb_dns_name" {
  description = "DNS name of the WordPress ALB"
  value       = aws_elb.wordpress_alb.dns_name
}

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  description = "CloudFront Distribution Domain Name"
  value       = aws_cloudfront_distribution.cdn.domain_name
}
