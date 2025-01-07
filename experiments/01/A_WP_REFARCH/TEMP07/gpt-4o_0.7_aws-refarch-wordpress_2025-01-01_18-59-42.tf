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
  description = "AWS region to deploy resources in"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "amis" {
  description = "Mapping of region to AMI"
  default     = { "us-east-1" = "ami-0c55b159cbfafe1f0" }
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "wordpress-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "wordpress-private-subnet-${count.index + 1}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "wordpress-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id
  description = "Allow web traffic"
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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress-web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id
  description = "Allow DB traffic from web sg"
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
    Name = "wordpress-db-sg"
  }
}

resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.main.id
  description = "Allow SSH from admin"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_ADMIN_IP/32"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "wordpress-bastion-sg"
  }
}

resource "aws_instance" "bastion" {
  ami                         = var.amis[var.region]
  instance_type               = "t2.micro"
  subnet_id                   = element(aws_subnet.public.*.id, 0)
  associate_public_ip_address = true
  security_groups             = [aws_security_group.bastion_sg.name]
  tags = {
    Name = "wordpress-bastion"
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  tags = {
    Name = "wordpress-bastion-eip"
  }
}

resource "aws_efs_file_system" "wordpress" {
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "wordpress-efs"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count          = length(aws_subnet.private)
  file_system_id = aws_efs_file_system.wordpress.id
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  security_groups = [aws_security_group.web_sg.id]
}

resource "aws_cloudwatch_metric_alarm" "efs_burst_credit_balance" {
  alarm_name          = "EFS Burst Credit Balance"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100000000"
  alarm_description   = "Alarm if burst credit balance is low."
  dimensions = {
    FileSystemId = aws_efs_file_system.wordpress.id
  }
}

resource "aws_elasticache_subnet_group" "wordpress_cache" {
  name       = "wordpress-cache"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_cluster" "wordpress" {
  cluster_id           = "wordpress-cache"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  subnet_group_name    = aws_elasticache_subnet_group.wordpress_cache.name
  security_group_ids   = [aws_security_group.web_sg.id]
  tags = {
    Name = "wordpress-cache"
  }
}

resource "aws_alb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id
  tags = {
    Name = "wordpress-alb"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Hello, world"
      status_code  = "200"
    }
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.wordpress.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "YOUR_CERTIFICATE_ARN"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Hello, world"
      status_code  = "200"
    }
  }
}

resource "aws_autoscaling_group" "wordpress" {
  desired_capacity     = 1
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.private[*].id
  launch_configuration = aws_launch_configuration.wordpress.id
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress" {
  name          = "wordpress-lc"
  image_id      = var.amis[var.region]
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd php mysql php-mysql
              service httpd start
              chkconfig httpd on
              EOF
}

resource "aws_rds_instance" "wordpress" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.small"
  name                 = "wordpressdb"
  username             = "admin"
  password             = "password"
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  tags = {
    Name = "wordpress-db"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-static-assets"
  acl    = "private"
  tags = {
    Name = "wordpress-assets"
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress_assets.bucket_regional_domain_name
    origin_id   = "S3-wordpress-static-assets"
  }
  enabled             = true
  default_cache_behavior {
    target_origin_id       = "S3-wordpress-static-assets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  price_class = "PriceClass_All"
  tags = {
    Name = "wordpress-cloudfront"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "wordpress"
  type    = "A"
  alias {
    name                   = aws_alb.wordpress.dns_name
    zone_id                = aws_alb.wordpress.zone_id
    evaluate_target_health = true
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "alb_dns_name" {
  value = aws_alb.wordpress.dns_name
}

output "rds_endpoint" {
  value = aws_rds_instance.wordpress.endpoint
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_assets.arn
}

output "cloudfront_url" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}
