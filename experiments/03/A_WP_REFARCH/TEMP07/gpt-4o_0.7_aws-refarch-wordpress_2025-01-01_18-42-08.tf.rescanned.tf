terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "AWS region to create resources in"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = list(string)
  description = "CIDR blocks for public subnets"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr" {
  type        = list(string)
  description = "CIDR blocks for private subnets"
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "allowed_ssh_ips" {
  type        = list(string)
  description = "List of CIDR blocks allowed to SSH"
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for WordPress"
  default     = "t2.micro"
}

variable "ami_id" {
  type        = string
  description = "AMI ID for EC2 instances"
  default     = "ami-0c55b159cbfafe1f0"
}

variable "db_instance_type" {
  type        = string
  description = "RDS instance type"
  default     = "db.t2.small"
}

variable "db_engine" {
  type        = string
  description = "Database engine for RDS"
  default     = "mysql"
}

variable "db_name" {
  type        = string
  description = "Database name"
  default     = "wordpress"
}

variable "db_username" {
  type        = string
  description = "Database username"
  default     = "admin"
}

variable "db_password" {
  type        = string
  description = "Database password"
  default     = "change_me"
}

variable "project_name" {
  type        = string
  description = "Name of the project"
  default     = "wordpress"
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidr)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnet_cidr, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index}"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidr)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidr, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index}"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "${var.project_name}-igw"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  vpc_id = aws_vpc.main.id

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
    cidr_blocks = var.allowed_ssh_ips
    description = "Allow SSH traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_security_group" "db" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
    description     = "Allow MySQL traffic from web instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-db-sg"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_launch_configuration" "wordpress" {
  name_prefix      = "${var.project_name}-lc-"
  image_id         = var.ami_id
  instance_type    = var.instance_type
  security_groups  = [aws_security_group.web.id]
  user_data        = <<-EOF
                      #!/bin/bash
                      yum update -y
                      yum install -y httpd php mysql
                      service httpd start
                      chkconfig httpd on
                      EOF
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress" {
  launch_configuration = aws_launch_configuration.wordpress.id
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.public.*.id

  tag {
    key                 = "Name"
    value               = "${var.project_name}-as"
    propagate_at_launch = true
  }
}

resource "aws_db_instance" "wordpress" {
  allocated_storage                 = 20
  engine                            = var.db_engine
  instance_class                    = var.db_instance_type
  name                              = var.db_name
  username                          = var.db_username
  password                          = var.db_password
  multi_az                          = true
  vpc_security_group_ids            = [aws_security_group.db.id]
  storage_encrypted                 = true
  backup_retention_period           = 7
  enabled_cloudwatch_logs_exports   = ["error", "general", "slowquery"]
  iam_database_authentication_enabled = true
  tags = {
    Name        = "${var.project_name}-rds"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_lb" "main" {
  name                      = "${var.project_name}-alb"
  internal                  = false
  load_balancer_type        = "application"
  security_groups           = [aws_security_group.web.id]
  subnets                   = aws_subnet.public.*.id
  enable_deletion_protection = true
  drop_invalid_header_fields = true
  tags = {
    Name        = "${var.project_name}-alb"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
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

resource "aws_lb_target_group" "main" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-tg"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_lb_target_group_attachment" "as" {
  count            = length(aws_autoscaling_group.wordpress.instances)
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = element(aws_autoscaling_group.wordpress.instances, count.index)
  port             = 80
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "${var.project_name}-origin"
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${var.project_name}-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  enabled = true
  viewer_certificate {
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.static_assets.bucket
  }

  tags = {
    Name        = "${var.project_name}-cf"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_s3_bucket" "static_assets" {
  bucket = "${var.project_name}-static-assets"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "${var.project_name}-logs"
    target_prefix = "s3/"
  }

  tags = {
    Name        = "${var.project_name}-static-assets"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_route53_zone" "main" {
  name = "example.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.example.com"
  type    = "A"
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cloudfront" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "cdn.example.com"
  type    = "CNAME"
  records = [aws_cloudfront_distribution.wordpress.domain_name]
  ttl     = 300
}

resource "aws_vpc_flow_log" "all" {
  vpc_id = aws_vpc.main.id
  log_destination_type = "cloud-watch-logs"
  log_group_name = "/aws/vpc/flowlogs/${var.project_name}"
  traffic_type = "ALL"
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "The DNS name of the ALB"
}

output "rds_endpoint" {
  value       = aws_db_instance.wordpress.endpoint
  description = "The endpoint of the RDS instance"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.wordpress.domain_name
  description = "The domain name of the CloudFront distribution"
}
