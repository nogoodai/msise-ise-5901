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
  type        = string
  description = "The AWS region where resources will be launched"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  type        = list(string)
  description = "List of IPs allowed to access via SSH"
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  type        = string
  description = "SSH key name for EC2 instances"
}

variable "ssl_certificate_arn" {
  type        = string
  description = "SSL Certificate ARN for HTTPS"
}

variable "domain_name" {
  type        = string
  description = "The domain name for the WordPress site"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPublicSubnet-${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPrivateSubnet-${count.index + 1}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
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
    description = "Allow HTTP from anywhere"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
    description = "Allow SSH from allowed IPs"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
    description     = "Allow MySQL access from web servers"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "WordPressRDSSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_db_instance" "wordpress_db" {
  engine                        = "mysql"
  instance_class                = "db.t2.small"
  allocated_storage             = 20
  name                          = "wordpressdb"
  username                      = "admin"
  password                      = var.db_password
  vpc_security_group_ids        = [aws_security_group.rds_sg.id]
  multi_az                      = true
  skip_final_snapshot           = true
  storage_encrypted             = true
  backup_retention_period       = 12
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public[0].id
  key_name                    = var.key_name
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true
  vpc_security_group_ids      = [aws_security_group.web_server_sg.id]
  tags = {
    Name        = "BastionHost"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  tags = {
    Name        = "BastionEIP"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  encrypted = true
  kms_key_id = var.kms_key_id
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name        = "WordPressEFS"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mount" {
  count           = length(aws_subnet.private)
  file_system_id  = aws_efs_file_system.wordpress_efs.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_server_sg.id]
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  engine              = "redis"
  node_type           = "cache.t2.micro"
  num_cache_nodes     = 1
  parameter_group_name = "default.redis5.0"
  port                = 6379
  subnet_group_name   = aws_elasticache_subnet_group.wordpress_cache_subnet_group.name
  security_group_ids  = [aws_security_group.web_server_sg.id]
  tags = {
    Name        = "WordPressCache"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_cache_subnet_group" {
  name       = "wordpress-cache-subnet"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name        = "WordPressCacheSubnetGroup"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_lb" "wordpress_alb" {
  name                        = "wordpress-alb"
  internal                    = false
  load_balancer_type          = "application"
  security_groups             = [aws_security_group.web_server_sg.id]
  subnets                     = aws_subnet.public[*].id
  enable_deletion_protection  = true
  drop_invalid_header_fields  = true
  tags = {
    Name        = "WordPressALB"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "redirect"
    redirect {
      protocol = "HTTPS"
      port     = "443"
      status_code = "HTTP_301"
    }
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
  tags = {
    Name        = "WordPressTargetGroup"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  vpc_zone_identifier = aws_subnet.private[*].id
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  min_size = 1
  max_size = 3
  desired_capacity = 1
  load_balancers = [aws_lb.wordpress_alb.name]

  tag {
    key                 = "Name"
    value               = "wordpress-instance"
    propagate_at_launch = true
  }
  tags = {
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_server_sg.id]
  user_data = <<-EOF
                #!/bin/bash
                yum update -y
                yum install -y httpd php php-mysql
                service httpd start
                chkconfig httpd on
                # Add more WordPress installation steps
                EOF
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-origin"
  }

  enabled             = true
  default_cache_behavior {
    target_origin_id   = "wordpress-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods    = ["GET", "HEAD", "OPTIONS"]
    cached_methods     = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  viewer_certificate {
    acm_certificate_arn = var.ssl_certificate_arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2018"
  }
  logging_config {
    include_cookies = false
    bucket          = var.cloudfront_logging_bucket
    prefix          = "wordpress"
  }
  tags = {
    Name        = "WordPressCloudFront"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket_log.id
    target_prefix = "log/"
  }
  tags = {
    Name        = "WordPressAssetsBucket"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "log" {
  bucket = "wordpress-log-bucket"
  acl    = "log-delivery-write"
  tags = {
    Name        = "WordPressLogBucket"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
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

output "alb_dns_name" {
  value       = aws_lb.wordpress_alb.dns_name
  description = "The DNS name of the ALB"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance"
}

output "efs_id" {
  value       = aws_efs_file_system.wordpress_efs.id
  description = "The ID of the EFS file system"
}
