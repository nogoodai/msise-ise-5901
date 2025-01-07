terraform {
  required_providers {
    aws = "= 5.1.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy into."
  default     = "us-west-2"
}

variable "admin_ip" {
  description = "IP address range allowed to SSH to EC2 instances."
  default     = "0.0.0.0/0"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "instance_type" {
  description = "Instance type for EC2 instances."
  default     = "t2.micro"
}

variable "ami" {
  description = "AMI ID for the WordPress instances."
  default     = "ami-0c55b159cbfafe1f0" // Amazon Linux 2
}

variable "db_instance_class" {
  description = "Instance class for RDS."
  default     = "db.t2.small"
}

variable "db_engine" {
  description = "Database engine for RDS."
  default     = "aurora"
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "wordpress-vpc"
  }
}

resource "aws_internet_gateway" "vpc_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "wordpress-igw"
  }
}

resource "aws_subnet" "public_subnet" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "public-subnet-${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name = "private-subnet-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpc_igw.id
  }
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Allow HTTP, HTTPS, and SSH inbound traffic"
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
    cidr_blocks = [var.admin_ip]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "web-sg"
  }
}

resource "aws_launch_configuration" "wordpress" {
  name                = "wordpress-lc"
  image_id            = var.ami
  instance_type       = var.instance_type
  security_groups     = [aws_security_group.web_sg.id]
  user_data_base64    = base64encode(data.template_file.user_data.rendered)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "wordpress" {
  desired_capacity     = 2
  max_size             = 5
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.public_subnet[*].id
  launch_configuration = aws_launch_configuration.wordpress.id
  health_check_type    = "ELB"
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-instance"
      propagate_at_launch = true
    }
  ]
}

resource "aws_alb" "wordpress" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public_subnet[*].id
  tags = {
    Name = "wordpress-alb"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.wordpress.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.wordpress.arn
  }
}

resource "aws_alb_target_group" "wordpress" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    path                = "/"
    timeout             = 5
  }
}

resource "aws_alb_target_group_attachment" "asg_attachment" {
  count               = length(aws_autoscaling_group.wordpress.instances)
  target_group_arn    = aws_alb_target_group.wordpress.arn
  target_id           = element(aws_autoscaling_group.wordpress.instances, count.index)
  port                = 80
}

resource "aws_rds_cluster" "wordpress" {
  cluster_identifier      = "wordpress-db-cluster"
  engine                  = var.db_engine
  engine_version          = "5.7.mysql_aurora.2.07.1"
  database_name           = "wordpress"
  master_username         = "admin"
  master_password         = "a-strong-password"
  skip_final_snapshot     = true
  backup_retention_period = 7
  availability_zones      = data.aws_availability_zones.available.names
  vpc_security_group_ids  = [aws_security_group.web_sg.id]
  tags = {
    Name = "wordpress-db"
  }
}

resource "aws_s3_bucket" "assets" {
  bucket_prefix = "wordpress-assets-"
  acl           = "public-read"

  tags = {
    Name = "wordpress-assets"
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id   = "s3-origin"
  }

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  tags = {
    Name = "wordpress-cdn"
  }
}

resource "aws_route53_zone" "main" {
  name = "example.com"
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_alb.wordpress.dns_name
    zone_id                = aws_alb.wordpress.zone_id
    evaluate_target_health = true
  }
}

data "aws_availability_zones" "available" {}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "template_file" "user_data" {
  template = <<EOF
#!/bin/bash
yum update -y
yum install -y httpd php php-mysqlnd
systemctl start httpd
systemctl enable httpd
EOF
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.wordpress_vpc.id
}

output "alb_dns_name" {
  description = "Load Balancer DNS"
  value       = aws_alb.wordpress.dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront Domain Name"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}
