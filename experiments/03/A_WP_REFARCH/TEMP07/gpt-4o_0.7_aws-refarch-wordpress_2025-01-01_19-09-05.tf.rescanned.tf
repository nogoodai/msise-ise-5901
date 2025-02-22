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
  type        = string
  default     = "us-east-1"
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

variable "ssh_key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "admin_ips" {
  description = "List of IPs allowed to SSH into servers"
  type        = list(string)
  default     = ["192.168.1.1/32"]
}

variable "ami_id" {
  description = "AMI ID for EC2 instances"
  type        = string
}

variable "instance_type" {
  description = "Instance type for EC2 instances"
  type        = string
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t2.small"
}

variable "db_engine" {
  description = "RDS database engine"
  type        = string
  default     = "mysql"
}

variable "alb_certificate_arn" {
  description = "ARN of the SSL certificate for ALB"
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

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
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
    Environment = "Production"
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
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name        = "WordPressPublicRT"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public_subnet" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Security group for web servers"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_ips
    description = "Allow SSH access from admin IPs"
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
  description = "Security group for database"

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description     = "Allow MySQL traffic from web servers"
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
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = element(aws_subnet.public[*].id, 0)
  key_name      = var.ssh_key_name
  associate_public_ip_address = false
  monitoring    = true

  vpc_security_group_ids = [aws_security_group.web_sg.id]

  tags = {
    Name        = "WordPressBastion"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  vpc      = true
}

resource "aws_efs_file_system" "wordpress" {
  encrypted = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name        = "WordPressEFS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count          = length(var.private_subnet_cidrs)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = element(aws_subnet.private[*].id, count.index)
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_burst_credit" {
  alarm_name          = "EFSBurstCreditAlarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "Alarm when EFS burst credits drop below threshold"
  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress.id
  }
}

resource "aws_elasticache_subnet_group" "wordpress" {
  name       = "wordpress-elasticache-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "wordpress" {
  cluster_id           = "wordpress-cache-cluster"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  subnet_group_name    = aws_elasticache_subnet_group.wordpress.name
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
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

resource "aws_launch_configuration" "wordpress" {
  name_prefix          = "wordpress-lc-"
  image_id             = var.ami_id
  instance_type        = var.instance_type
  security_groups      = [aws_security_group.web_sg.id]
  associate_public_ip_address = false
  user_data            = file("wordpress-bootstrap.sh")
  key_name             = var.ssh_key_name
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public[*].id
  launch_configuration = aws_launch_configuration.wordpress.id
  target_group_arns    = [aws_lb_target_group.wordpress_tg.arn]
  health_check_type    = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "WordPressInstance"
    propagate_at_launch = true
  }

  tags = {
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_rds_instance" "wordpress_db" {
  identifier              = "wordpress-db"
  instance_class          = var.db_instance_class
  engine                  = var.db_engine
  allocated_storage       = 20
  db_subnet_group_name    = aws_db_subnet_group.wordpress.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  multi_az                = true
  storage_encrypted       = true
  backup_retention_period = 7
  skip_final_snapshot     = true

  tags = {
    Name        = "WordPressDB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "WordPressDBSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_id.hex}"
  acl    = "private"

  logging {
    target_bucket = aws_s3_bucket_log.bucket
    target_prefix = "log/"
  }

  versioning {
    enabled = true
  }

  tags = {
    Name        = "WordPressAssets"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_s3_bucket" "log" {
  bucket = "wordpress-logs-${random_id.log_bucket_id.hex}"
  acl    = "log-delivery-write"
}

resource "random_id" "log_bucket_id" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress" {
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
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2019"
    acm_certificate_arn            = var.alb_certificate_arn
    ssl_support_method             = "sni-only"
  }

  logging_config {
    bucket = aws_s3_bucket.log.bucket_regional_domain_name
    include_cookies = false
    prefix = "cloudfront/"
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"

  tags = {
    Name        = "WordPressRoute53"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value       = aws_vpc.wordpress_vpc.id
  description = "The ID of the VPC"
}

output "alb_dns_name" {
  value       = aws_lb.wordpress_alb.dns_name
  description = "The DNS name of the ALB"
}

output "rds_endpoint" {
  value       = aws_rds_instance.wordpress_db.endpoint
  description = "The endpoint of the RDS instance"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_assets.id
  description = "The name of the S3 bucket"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "bastion_eip" {
  value       = aws_eip.bastion_eip.public_ip
  description = "The public IP of the bastion host"
}
