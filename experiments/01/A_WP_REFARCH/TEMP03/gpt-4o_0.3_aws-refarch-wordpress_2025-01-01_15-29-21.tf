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
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  default     = "10.0.2.0/24"
}

variable "allowed_ssh_ips" {
  description = "List of IPs allowed to SSH into bastion and web servers"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  default     = "db.t2.small"
}

variable "db_engine" {
  description = "Database engine for RDS"
  default     = "mysql"
}

variable "db_name" {
  description = "Database name for WordPress"
  default     = "wordpress"
}

variable "db_username" {
  description = "Master username for the database"
  default     = "admin"
}

variable "db_password" {
  description = "Master password for the database"
  default     = "changeMe123!"
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

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags = {
    Name = "WordPressPublicSubnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.region}a"
  tags = {
    Name = "WordPressPrivateSubnet"
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

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
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
    Name = "WordPressWebSG"
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
    Name = "WordPressDBSG"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
  key_name      = var.key_name
  security_groups = [aws_security_group.web_sg.name]
  associate_public_ip_address = true
  tags = {
    Name = "BastionHost"
  }
}

resource "aws_eip" "bastion_eip" {
  instance = aws_instance.bastion.id
  tags = {
    Name = "BastionEIP"
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "WordPressEFS"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mt" {
  for_each = toset([aws_subnet.public_subnet.id, aws_subnet.private_subnet.id])
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = each.value
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_alarm" {
  alarm_name          = "EFSBurstCreditBalanceAlarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100000000"
  alarm_description   = "Alarm when EFS burst credit balance is low"
  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress_efs.id
  }
}

resource "aws_elasticache_subnet_group" "wordpress_cache_subnet_group" {
  name       = "wordpress-cache-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id]
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_cache_subnet_group.name
  security_group_ids   = [aws_security_group.web_sg.id]
  parameter_group_name = "default.redis3.2"
  tags = {
    Name = "WordPressCache"
  }
}

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = [aws_subnet.public_subnet.id]
  tags = {
    Name = "WordPressALB"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
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
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.private_subnet.id]
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  target_group_arns    = [aws_lb_target_group.wordpress_tg.arn]
  tags = [{
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php php-mysql
              service httpd start
              chkconfig httpd on
              EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = var.db_engine
  engine_version       = "5.7"
  instance_class       = var.db_instance_class
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az             = true
  tags = {
    Name = "WordPressDB"
  }
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id]
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets-${random_id.bucket_id.hex}"
  acl    = "public-read"
  tags = {
    Name = "WordPressAssets"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-WordPressAssets"
  }
  enabled             = true
  is_ipv6_enabled     = true
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
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  tags = {
    Name = "WordPressCloudFront"
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

resource "aws_route53_record" "wordpress_cf_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "cdn.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.wordpress_cf.domain_name]
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

output "vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress_db.endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_assets.bucket
}
