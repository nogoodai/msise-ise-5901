terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-gw"
  }
}

resource "aws_subnet" "public_subnet" {
  count = 2
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress-public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count = 2
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, 2 + count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "wordpress-private-subnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "wordpress-public-rt"
  }
}

resource "aws_route_table_association" "public_subnet" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
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
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "web-server-sg"
  }
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access to bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]
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
    Name = "database-sg"
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.latest.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet[0].id
  security_groups = [
    aws_security_group.web_sg.name
  ]

  key_name = var.bastion_key_name

  associate_public_ip_address = true

  tags = {
    Name = "BastionHost"
  }
}

variable "bastion_key_name" {
  description = "SSH key name for bastion host access"
  type        = string
}

data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_efs_file_system" "wordpress_efs" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "wordpress-efs"
  }
}

resource "aws_efs_mount_target" "wordpress_efs_mt" {
  count          = 2
  file_system_id = aws_efs_file_system.wordpress_efs.id
  subnet_id      = aws_subnet.private_subnet[count.index].id
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_alarm" {
  alarm_name          = "EFS-put-to-throughput-exceeded"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Sum"
  threshold           = 10

  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress_efs.id
  }

  alarm_description = "This metric monitors when to throughput is exceeded on EFS"
}

resource "aws_elasticache_cluster" "wordpress_cache" {
  cluster_id           = "wordpress-cache"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_cache_sg.name
  security_group_ids   = [aws_security_group.web_sg.id]

  tags = {
    Name = "wordpress-cache"
  }
}

resource "aws_elasticache_subnet_group" "wordpress_cache_sg" {
  name       = "wordpress-cache-sng"
  subnet_ids = aws_subnet.private_subnet[*].id
}

resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public_subnet[*].id

  tags = {
    Name = "wordpress-alb"
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
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "wordpress-tg"
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public_subnet[*].id
  target_group_arns    = [aws_lb_target_group.wordpress_tg.arn]

  launch_configuration = aws_launch_configuration.wordpress_launch_config.id

  tags = [
    {
      key                 = "Name"
      value               = "wordpress-instance"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "wordpress-launch-config"
  image_id      = data.aws_ami.latest.id
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.web_sg.id
  ]

  user_data = <<-EOF
        #!/bin/bash
        yum update -y
        yum install -y httpd
        systemctl start httpd
        systemctl enable httpd
    EOF
}

resource "aws_db_instance" "wordpress_db" {
  identifier               = "wordpress-db"
  instance_class           = "db.t2.small"
  allocated_storage        = 20
  engine                   = "mysql"
  engine_version           = "8.0"
  name                     = "wordpress"
  username                 = var.db_username
  password                 = var.db_password
  vpc_security_group_ids   = [aws_security_group.db_sg.id]
  db_subnet_group_name     = aws_db_subnet_group.wordpress_db_sg.name
  multi_az                 = true
  backup_retention_period  = 7
  skip_final_snapshot      = true

  tags = {
    Name = "wordpress-db"
  }
}

resource "aws_db_subnet_group" "wordpress_db_sg" {
  name       = "wordpress-db-sg"
  subnet_ids = aws_subnet.private_subnet[*].id
  tags = {
    Name = "wordpress-db-sg"
  }
}

variable "db_username" {
  description = "The database username"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "The database password"
  type        = string
  default     = "password"
  sensitive   = true
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  enabled             = true
  origin {
    domain_name = aws_lb.wordpress_alb.dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
    }
  }

  default_cache_behavior {
    target_origin_id       = "wordpress-alb"
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    default_ttl            = 3600
    forwarded_values {
      query_string = false
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }
  }

  tags = {
    Name = "wordpress-cf"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets-${random_string.bucket_suffix.result}"
  acl    = "public-read"

  tags = {
    Name = "wordpress-assets-bucket"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
}

resource "aws_route53_zone" "wordpress" {
  name = var.domain_name

  tags = {
    Name = "wordpress-route53"
  }
}

resource "aws_route53_record" "wordpress_alb" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

variable "domain_name" {
  description = "Domain name for the WordPress site"
  type        = string
  default     = "example.com"
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
  value = aws_cloudfront_distribution.wordpress_cf.domain_name
}
