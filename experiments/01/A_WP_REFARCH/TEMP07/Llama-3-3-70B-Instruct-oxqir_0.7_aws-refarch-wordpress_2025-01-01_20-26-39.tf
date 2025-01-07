# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.16.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Define variables
variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "instance_type" {
  default = "t2.micro"
}

variable "ami_id" {
  default = "ami-0c94855ba95c71c99"
}

variable "db_instance_class" {
  default = "db.t2.small"
}

variable "db_username" {
  default = "wordpressuser"
}

variable "db_password" {
  default = "wordpresspassword"
}

variable "db_name" {
  default = "wordpressdb"
}

variable "cloudfront_domain_name" {
  default = "example.com"
}

variable "route53_zone_name" {
  default = "example.com"
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets configuration
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.availability_zones[0]
  tags = {
    Name = "PublicSubnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = var.availability_zones[0]
  tags = {
    Name = "PrivateSubnet"
  }
}

# Internet Gateway configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "WordPressIGW"
  }
}

# Route Tables configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Route Table Associations configuration
resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_route_table_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups configuration
resource "aws_security_group" "wordpress_sg" {
  name        = "WordPressSG"
  description = "Security Group for WordPress instances"
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
  tags = {
    Name = "WordPressSG"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "RDSSG"
  description = "Security Group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "RDSSG"
  }
}

# EC2 configuration
resource "aws_instance" "wordpress_instance" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_sg.id
  ]
  subnet_id = aws_subnet.private_subnet.id
  tags = {
    Name = "WordPressInstance"
  }
}

# RDS configuration
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.db_instance_class
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressDB"
  }
}

# DB Subnet Group configuration
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "WordPressDBSubnetGroup"
  subnet_ids = [aws_subnet.private_subnet.id]
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer configuration
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.wordpress_sg.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = 5
  min_size                  = 1
  desired_capacity          = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.private_subnet.id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
  ]
}

# Launch Configuration configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_sg.id
  ]
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront configuration
resource "aws_cloudfront_distribution" "wordpress_cdf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled = true
  default_root_object = "index.html"
  aliases = [var.cloudfront_domain_name]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "WordPressELB"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_acm_certificate.arn
    ssl_support_method  = "sni-only"
  }
}

# ACM Certificate configuration
resource "aws_acm_certificate" "wordpress_acm_certificate" {
  domain_name       = var.cloudfront_domain_name
  validation_method = "DNS"
}

# Route 53 configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.route53_zone_name
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.route53_zone_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdf.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cdf.zone_id
    evaluate_target_health = false
  }
}

# S3 Bucket configuration
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket = "wordpress-s3-bucket"
  acl    = "private"
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_cdf_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cdf.domain_name
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.id
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.id
}
