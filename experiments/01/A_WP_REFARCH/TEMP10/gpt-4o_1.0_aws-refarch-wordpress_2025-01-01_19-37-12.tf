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
  default = "us-east-1"
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

variable "admin_ssh_cidr" {
  description = "CIDR block for SSH access"
  default     = "0.0.0.0/0"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for static assets"
  default     = "wordpress-static-assets-bucket"
}

variable "wordpress_instance_type" {
  default = "t2.micro"
}

variable "db_instance_class" {
  default = "db.t2.small"
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

resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "WordPressPublicSubnet-${count.index + 1}"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "WordPressPrivateSubnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "WordPressPublicRouteTable"
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Allow HTTP, HTTPS and SSH access"

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
    cidr_blocks = [var.admin_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "WordPressSG"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Allow MySQL access from WordPress instances"

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
    Name = "WordPressDBSG"
  }
}

resource "aws_instance" "bastion" {
  ami                         = "ami-053b0d53c279acc90" # Amazon Linux 2
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  subnet_id                   = aws_subnet.public_subnets[0].id
  key_name                    = "wordpress-key"
  associate_public_ip_address = true

  tags = {
    Name = "BastionHost"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
}

resource "aws_efs_file_system" "wordpress" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  throughput_mode = "bursting"
  
  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "efs_mount_targets" {
  count          = length(aws_subnet.private_subnets)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = element(aws_subnet.private_subnets[*].id, count.index)
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_credits" {
  alarm_name          = "EFS BurstCreditBalanceLow"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Average"
  threshold           = 10000000.0
  alarm_description   = "Alert if EFS Burst Credit balance is low."
  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress.id
  }
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id      = "wordpress-cache"
  engine          = "memcached"
  engine_version  = "1.6.6"
  node_type       = "cache.t2.micro"
  num_cache_nodes = 1

  parameter_group_name = "default.memcached1.6"

  subnet_group_name = aws_elasticache_subnet_group.cache_subnets.name

  tags = {
    Name = "WordPressCache"
  }
}

resource "aws_elasticache_subnet_group" "cache_subnets" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id

  tags = {
    Name = "WordPressCacheSubnetGroup"
  }
}

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  enable_deletion_protection = true

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

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }

  certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcdefghi-1234-hijklm-5678-nopqrstuvw"
}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    interval            = 30
    path                = "/"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = {
    Name = "WordPressTargetGroup"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 2
  vpc_zone_identifier  = aws_subnet.private_subnets[*].id
  launch_configuration = aws_launch_configuration.wordpress_lc.id
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
  name          = "wordpress-launch-configuration"
  image_id      = "ami-053b0d53c279acc90" # Amazon Linux 2
  instance_type = var.wordpress_instance_type
  security_groups = [aws_security_group.web_sg.id]
  key_name       = "wordpress-key"
  user_data      = file("bootstrap.sh")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = "admin123"
  parameter_group_name = "default.mysql5.7"
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CloudFront Distribution"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-alb"

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

  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcdefghi-1234-hijklm-5678-nopqrstuvw"
    ssl_support_method  = "sni-only"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = var.s3_bucket_name
  acl    = "public-read"

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }

  tags = {
    Name = "WordPressS3Assets"
  }
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "www.example.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

output "elb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "db_instance_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.id
}

output "bastion_host_ip" {
  value = aws_eip.bastion_eip.public_ip
}
