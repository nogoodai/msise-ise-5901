terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in."
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  description = "Allowed IPs for SSH access."
  default     = ["0.0.0.0/0"]
}

variable "ami_id" {
  description = "AMI ID for EC2 instances."
  default     = "ami-0c55b159cbfafe1f0" # Amazon Linux 2
}

variable "instance_type" {
  description = "Instance type for EC2 instances."
  default     = "t2.micro"
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
    Name = "PublicSubnet-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
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

resource "aws_instance" "bastion" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public[0].id
  key_name      = aws_key_pair.bastion_key.key_name
  associate_public_ip_address = true
  security_groups = [aws_security_group.web_sg.name]
  tags = {
    Name = "BastionHost"
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "bastion-key"
  public_key = file(var.public_key_path)
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  vpc      = true
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  performance_mode = "generalPurpose"
  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_cache_subnet_group.name
  security_group_ids   = [aws_security_group.web_sg.id]
  tags = {
    Name = "WordPressCache"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_cache_subnet_group" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id
  tags = {
    Name = "WordPressALB"
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

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate_arn
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.public[*].id
  target_group_arns    = [aws_lb_target_group.wordpress_tg.arn]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressInstance"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysqlnd
              systemctl start httpd
              systemctl enable httpd
              EOF
}

resource "aws_db_instance" "wordpress_db" {
  identifier              = "wordpress-db"
  engine                  = "mysql"
  instance_class          = "db.t2.small"
  allocated_storage       = 20
  name                    = "wordpress"
  username                = "admin"
  password                = "password"
  multi_az                = true
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_string.bucket_suffix.result}"
  acl    = "public-read"
  tags = {
    Name = "WordPressAssets"
  }
}

resource "random_string" "bucket_suffix" {
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
  default_root_object = "index.html"
  default_cache_behavior {
    target_origin_id       = "S3-wordpress-assets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
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
  price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  tags = {
    Name = "WordPressCDN"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_alb_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "db_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}
