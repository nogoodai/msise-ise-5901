terraform {
  required_providers {
    aws = "= 5.1.0"
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "allowed_ssh_ips" {
  description = "Allowed IPs for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "environment" {
  description = "The environment for the deployment"
  type        = string
  default     = "production"
}

variable "key_name" {
  description = "SSH key name for EC2 instances"
  type        = string
}

variable "domain_name" {
  description = "The domain name for Route 53"
  type        = string
}

resource "random_id" "bucket_id" {
  byte_length = 8
}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "wordpress-vpc"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name        = "wordpress-public-subnet-${count.index}"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.wordpress_vpc.cidr_block, 8, count.index + 2)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name        = "wordpress-private-subnet-${count.index}"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = var.environment
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
    Name        = "wordpress-public-route-table"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Allow web traffic"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_ips
    description = "SSH"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
  tags = {
    Name        = "wordpress-web-sg"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_security_group" "database" {
  vpc_id = aws_vpc.wordpress_vpc.id
  description = "Allow database traffic"
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
    description     = "MySQL access from web servers"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
  tags = {
    Name        = "wordpress-db-sg"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_instance" "bastion" {
  ami           = "ami-0c55b159cbfafe1f0" 
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[0].id
  key_name      = var.key_name
  associate_public_ip_address = false
  vpc_security_group_ids = [aws_security_group.web.id]
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "wordpress-bastion"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  tags = {
    Name        = "wordpress-bastion-eip"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_efs_file_system" "wordpress" {
  encrypted = true
  kms_key_id = var.kms_key_id
  tags = {
    Name        = "wordpress-efs"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_efs_mount_target" "wordpress" {
  count           = length(aws_subnet.private)
  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.web.id]
}

resource "aws_launch_template" "wordpress" {
  name_prefix   = "wordpress-"
  image_id      = "ami-0c55b159cbfafe1f0" 
  instance_type = "t2.micro"
  key_name      = var.key_name
  network_interfaces {
    security_groups = [aws_security_group.web.id]
  }
  user_data = base64encode("#!/bin/bash\namazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2\nsystemctl start httpd\nsystemctl enable httpd\n")
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "wordpress-instance"
      Environment = var.environment
      Project     = "WordPress"
    }
  }
}

resource "aws_autoscaling_group" "wordpress" {
  launch_template {
    id      = aws_launch_template.wordpress.id
    version = "$Latest"
  }
  vpc_zone_identifier = aws_subnet.public[*].id
  min_size            = 1
  max_size            = 3
  desired_capacity    = 1
  load_balancers      = [aws_elb.wordpress.id]
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "WordPress"
      propagate_at_launch = true
    },
  ]
}

resource "aws_elb" "wordpress" {
  name               = "wordpress-elb"
  availability_zones = data.aws_availability_zones.available.names
  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  listener {
    instance_port     = 443
    instance_protocol = "HTTPS"
    lb_port           = 443
    lb_protocol       = "HTTPS"
  }
  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  access_logs {
    bucket = aws_s3_bucket.elb_logs.bucket
    enabled = true
  }
  security_groups = [aws_security_group.web.id]
  tags = {
    Name        = "wordpress-elb"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route53_zone" "wordpress" {
  name = var.domain_name
  tags = {
    Name        = "wordpress-route53"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.wordpress.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress.dns_name
    zone_id                = aws_elb.wordpress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_db_instance" "wordpress" {
  engine                       = "mysql"
  instance_class               = "db.t2.small"
  allocated_storage            = 20
  name                         = "wordpressdb"
  username                     = "admin"
  password                     = var.db_password
  multi_az                     = true
  vpc_security_group_ids       = [aws_security_group.database.id]
  storage_encrypted            = true
  backup_retention_period      = 12
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  tags = {
    Name        = "wordpress-db"
    Environment = var.environment
    Project     = "WordPress"
  }
}

variable "db_password" {
  description = "The password for the RDS instance"
  type        = string
  sensitive   = true
}

resource "aws_s3_bucket" "wordpress" {
  bucket = "wordpress-static-assets-${random_id.bucket_id.hex}"
  acl    = "private"
  logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/"
  }
  versioning {
    enabled = true
  }
  tags = {
    Name        = "wordpress-static-assets"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "wordpress-log-bucket-${random_id.bucket_id.hex}"
  acl    = "log-delivery-write"
  tags = {
    Name        = "wordpress-log-bucket"
    Environment = var.environment
    Project     = "WordPress"
  }
}

resource "aws_cloudfront_distribution" "wordpress" {
  origin {
    domain_name = aws_s3_bucket.wordpress.bucket_regional_domain_name
    origin_id   = "S3-wordpress-static-assets"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-wordpress-static-assets"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }
  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2019"
  }
  tags = {
    Name        = "wordpress-cdn"
    Environment = var.environment
    Project     = "WordPress"
  }
}

variable "acm_certificate_arn" {
  description = "The ARN of the ACM certificate for CloudFront"
  type        = string
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.wordpress_vpc.id
}

output "elb_dns_name" {
  description = "DNS name of the ELB"
  value       = aws_elb.wordpress.dns_name
}

output "db_instance_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.wordpress.endpoint
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}
