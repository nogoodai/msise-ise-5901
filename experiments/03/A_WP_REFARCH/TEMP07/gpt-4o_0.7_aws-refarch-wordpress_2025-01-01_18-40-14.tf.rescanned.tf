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
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for the public subnets"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR blocks for the private subnets"
}

variable "allowed_ssh_ips" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Allowed IPs for SSH access"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "key_name" {
  type        = string
  default     = "my-key-pair"
  description = "Key pair name for EC2 instances"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS database"
}

variable "db_engine" {
  type        = string
  default     = "mysql"
  description = "Database engine for RDS instance"
}

variable "db_name" {
  type        = string
  default     = "wordpressdb"
  description = "Database name for WordPress"
}

variable "db_username" {
  type        = string
  default     = "admin"
  description = "Database username"
}

variable "db_password" {
  type        = string
  default     = "password"
  description = "Database password"
}

variable "alb_certificate_arn" {
  type        = string
  default     = "arn:aws:acm:us-east-1:123456789012:certificate/abcdefg-1234-5678-abcd-ef1234567890"
  description = "ARN of the certificate for ALB"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for Route 53"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "WordPressVPC"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PublicSubnet-${count.index + 1}"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "PrivateSubnet-${count.index + 1}"
    Environment = "production"
    Project = "WordPress"
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
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for web servers"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
    description = "Allow HTTP"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
    description = "Allow HTTPS"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
    description = "Allow SSH"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name = "WebServerSG"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for RDS database"
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
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
    Name = "DatabaseSG"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami                         = "ami-0c55b159cbfafe1f0" # Example AMI
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  tags = {
    Name = "BastionHost"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  tags = {
    Name = "BastionEIP"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  encrypted = true
  kms_key_id = aws_kms_key.wordpress_kms.arn
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "WordPressEFS"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mt" {
  count           = length(var.private_subnet_cidrs)
  file_system_id  = aws_efs_file_system.wordpress_efs.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_db_instance" "wordpress_rds" {
  allocated_storage             = 20
  storage_type                  = "gp2"
  engine                        = var.db_engine
  engine_version                = "5.7"
  instance_class                = var.db_instance_class
  name                          = var.db_name
  username                      = var.db_username
  password                      = var.db_password
  vpc_security_group_ids        = [aws_security_group.db_sg.id]
  multi_az                      = true
  publicly_accessible           = false
  skip_final_snapshot           = true
  storage_encrypted             = true
  backup_retention_period       = 7
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  tags = {
    Name = "WordPressDB"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_lb" "wordpress_alb" {
  name                        = "wordpress-alb"
  internal                    = false
  load_balancer_type          = "application"
  security_groups             = [aws_security_group.web_sg.id]
  subnets                     = aws_subnet.public[*].id
  enable_deletion_protection  = true
  drop_invalid_header_fields  = true
  tags = {
    Name = "WordPressALB"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
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
  certificate_arn   = var.alb_certificate_arn
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
    Name = "WordPressTG"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private[*].id
  target_group_arns    = [aws_lb_target_group.wordpress_tg.arn]
  launch_configuration = aws_launch_configuration.wordpress_lc.id
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
  image_id      = "ami-0c55b159cbfafe1f0" # Example AMI
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.web_sg.id]
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd wordpress php mysql
    systemctl start httpd
    systemctl enable httpd
    # Additional WordPress configuration
  EOF
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_id.hex}"
  acl    = "private"
  logging {
    target_bucket = "log-bucket"
    target_prefix = "log/"
  }
  versioning {
    enabled = true
  }
  tags = {
    Name = "WordPressAssets"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-Origin"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_cache_behavior {
    target_origin_id       = "S3-Origin"
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
    default_ttl           = 3600
    max_ttl               = 86400
  }
  price_class         = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = false
    minimum_protocol_version = "TLSv1.2_2018"
    acm_certificate_arn = var.alb_certificate_arn
  }
  logging_config {
    bucket = "log-bucket.s3.amazonaws.com"
    include_cookies = false
    prefix = "cloudfront/"
  }
  tags = {
    Name = "WordPressCloudFront"
    Environment = "production"
    Project = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
  tags = {
    Name = "WordPressRoute53Zone"
    Environment = "production"
    Project = "WordPress"
  }
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
  value       = aws_vpc.wordpress_vpc.id
  description = "VPC ID for WordPress infrastructure"
}

output "alb_dns_name" {
  value       = aws_lb.wordpress_alb.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "Endpoint for the WordPress RDS instance"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
  description = "Domain name for the CloudFront distribution"
}
