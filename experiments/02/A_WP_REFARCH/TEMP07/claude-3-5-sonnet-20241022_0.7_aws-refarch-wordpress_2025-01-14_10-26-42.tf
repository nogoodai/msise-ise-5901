terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  default = "us-west-2"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "environment" {
  default = "production"
}

variable "domain_name" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

# VPC and Networking
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                 = aws_vpc.wordpress_vpc.id
  cidr_block             = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone      = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "wordpress-public-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count              = 2
  vpc_id             = aws_vpc.wordpress_vpc.id
  cidr_block         = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone  = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "wordpress-private-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "wordpress-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "wordpress-alb-"
  vpc_id      = aws_vpc.wordpress_vpc.id

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

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "wordpress-alb-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "wordpress" {
  name_prefix = "wordpress-ec2-"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "wordpress-ec2-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "wordpress-rds-"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress.id]
  }

  tags = {
    Name        = "wordpress-rds-sg"
    Environment = var.environment
  }
}

# RDS Instance
resource "aws_db_subnet_group" "wordpress" {
  name       = "wordpress-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "wordpress-db-subnet"
    Environment = var.environment
  }
}

resource "aws_rds_cluster" "wordpress" {
  cluster_identifier     = "wordpress-db-cluster"
  engine                = "aurora-mysql"
  engine_version        = "5.7.mysql_aurora.2.10.2"
  database_name         = "wordpress"
  master_username       = "admin"
  master_password       = var.db_password
  db_subnet_group_name  = aws_db_subnet_group.wordpress.name
  skip_final_snapshot   = true
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  tags = {
    Name        = "wordpress-aurora-cluster"
    Environment = var.environment
  }
}

resource "aws_rds_cluster_instance" "wordpress" {
  count               = 2
  identifier          = "wordpress-aurora-${count.index}"
  cluster_identifier  = aws_rds_cluster.wordpress.id
  instance_class      = "db.r5.large"
  engine              = aws_rds_cluster.wordpress.engine
  engine_version      = aws_rds_cluster.wordpress.engine_version

  tags = {
    Name        = "wordpress-aurora-${count.index}"
    Environment = var.environment
  }
}

# S3 Bucket
resource "aws_s3_bucket" "wordpress" {
  bucket_prefix = "wordpress-assets-"

  tags = {
    Name        = "wordpress-assets"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "wordpress" {
  bucket = aws_s3_bucket.wordpress.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "wordpress" {
  bucket = aws_s3_bucket.wordpress.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.php"

  origin {
    domain_name = aws_lb.wordpress.dns_name
    origin_id   = "wordpress-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = "wordpress-alb"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "wordpress-cdn"
    Environment = var.environment
  }
}

# Application Load Balancer
resource "aws_lb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = true

  tags = {
    Name        = "wordpress-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "wordpress" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 15
    matcher            = "200"
    path               = "/wp-admin/install.php"
    port               = "traffic-port"
    timeout            = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "wordpress-tg"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.wordpress.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress.arn
  }
}

# Auto Scaling Group
resource "aws_launch_template" "wordpress" {
  name_prefix   = "wordpress-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.small"

  network_interfaces {
    associate_public_ip_address = false
    security_groups            = [aws_security_group.wordpress.id]
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_host     = aws_rds_cluster.wordpress.endpoint
    db_name     = aws_rds_cluster.wordpress.database_name
    db_user     = aws_rds_cluster.wordpress.master_username
    db_password = var.db_password
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "wordpress-instance"
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress" {
  name                = "wordpress-asg"
  target_group_arns   = [aws_lb_target_group.wordpress.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  vpc_zone_identifier = aws_subnet.private[*].id
  
  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "wordpress-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# Route 53
resource "aws_route53_zone" "wordpress" {
  name = var.domain_name

  tags = {
    Name        = "wordpress-zone"
    Environment = var.environment
  }
}

resource "aws_route53_record" "wordpress" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress.hosted_zone_id
    evaluate_target_health = false
  }
}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Outputs
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.wordpress.domain_name
}

output "rds_endpoint" {
  value = aws_rds_cluster.wordpress.endpoint
}

output "alb_dns_name" {
  value = aws_lb.wordpress.dns_name
}
