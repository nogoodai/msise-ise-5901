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
  default     = "us-west-2"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "The CIDR blocks for public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "The CIDR blocks for private subnets."
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  type        = list(string)
}

variable "allowed_ssh_ips" {
  description = "The IP addresses allowed to SSH into instances."
  default     = ["0.0.0.0/0"]
  type        = list(string)
}

variable "instance_type" {
  description = "The EC2 instance type for WordPress instances."
  default     = "t2.micro"
  type        = string
}

variable "db_instance_class" {
  description = "The RDS instance class."
  default     = "db.t2.small"
  type        = string
}

variable "db_name" {
  description = "The name of the WordPress database."
  default     = "wordpress"
  type        = string
}

variable "db_username" {
  description = "The master username for the RDS instance."
  default     = "admin"
  type        = string
}

variable "db_password" {
  description = "The master password for the RDS instance."
  default     = "yourpassword"
  sensitive   = true
  type        = string
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = false
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPublicSubnet${count.index}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "WordPressPrivateSubnet${count.index}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
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
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for WordPress web tier."
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = []
    description = "HTTP access"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = []
    description = "HTTPS access"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
    description = "SSH access"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "WordPressWebSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for WordPress database tier."
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description     = "MySQL access from WordPress web tier"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "WordPressDBSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public[0].id
  associate_public_ip_address = false
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  monitoring             = true
  ebs_optimized          = true
  tags = {
    Name        = "WordPressBastionHost"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  tags = {
    Name        = "WordPressBastionEIP"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  encrypted = true
  kms_key_id = var.efs_kms_key_id
  tags = {
    Name        = "WordPressEFS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "efs_mount" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_burst_balance" {
  alarm_name          = "EFSBurstBalanceAlarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000000000"
  alarm_actions       = []
  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress_efs.id
  }
  tags = {
    Name        = "EFSBurstBalanceAlarm"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_cache_subnet" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
  tags = {
    Name        = "WordPressCacheSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_cache_subnet.name
  security_group_ids   = [aws_security_group.web_sg.id]
  snapshot_retention_limit = 5
  tags = {
    Name        = "WordPressCacheCluster"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id
  enable_deletion_protection = true
  drop_invalid_header_fields = true
  tags = {
    Name        = "WordPressALB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_target_group.arn
  }
}

resource "aws_lb_target_group" "wordpress_target_group" {
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
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public[*].id
  target_group_arns    = [aws_lb_target_group.wordpress_target_group.arn]

  launch_configuration = aws_launch_configuration.wordpress_lc.id
  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
  tags = {
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php mysql php-mysql
              service httpd start
              chkconfig httpd on
              EOF
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage           = 20
  storage_type                = "gp2"
  engine                      = "mysql"
  engine_version              = "5.7"
  instance_class              = var.db_instance_class
  name                        = var.db_name
  username                    = var.db_username
  password                    = var.db_password
  parameter_group_name        = "default.mysql5.7"
  multi_az                    = true
  vpc_security_group_ids      = [aws_security_group.db_sg.id]
  storage_encrypted           = true
  backup_retention_period     = 12
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  tags = {
    Name        = "WordPressDB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_string.bucket_id.result}"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name        = "WordPressAssets"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "random_string" "bucket_id" {
  length  = 8
  special = false
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-WordPressAssets"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-WordPressAssets"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.ssl_certificate_arn
    minimum_protocol_version       = "TLSv1.2_2019"
    cloudfront_default_certificate = false
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "Production"
    Project     = "WordPress"
  }
}

data "aws_route53_zone" "selected" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "wordpress.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wordpress_cf" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.wordpress_cf.domain_name]
}

output "wordpress_alb_dns" {
  value       = aws_lb.wordpress_alb.dns_name
  description = "The DNS name of the WordPress ALB."
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_db.endpoint
  description = "The endpoint of the WordPress RDS instance."
}

output "wordpress_cf_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
  description = "The domain name of the WordPress CloudFront distribution."
}
