# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration
provider "aws" {
  region = var.region
}

# Variables
variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS Region"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  description = "List of Availability Zones"
}

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR Block"
}

variable "wordpress_ami" {
  type        = string
  default     = "ami-0c94855ba95c71c99" # Replace with your desired AMI
  description = "AMI ID for WordPress instances"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for WordPress instances"
}

variable "database_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "bucket_name" {
  type        = string
  default     = "wordpress-static-assets"
  description = "S3 bucket name for static assets"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for CloudFront distribution"
}

variable "ssh_key_name" {
  type        = string
  default     = "wordpress-ssh-key"
  description = "SSH key name for EC2 instances"
}

# Networking

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "public_subnets" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone      = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "PublicSubnet-${count.index}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnets" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 8, count.index + length(var.availability_zones))
  availability_zone      = var.availability_zones[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name        = "PrivateSubnet-${count.index}"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public_subnets_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "private_subnets_association" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups

resource "aws_security_group" "web_server_sg" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  name        = "WordPressWebServerSG"
  description = "Security group for WordPress web servers"
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
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "database_sg" {
  vpc_id      = aws_vpc.wordpress_vpc.id
  name        = "WordPressDatabaseSG"
  description = "Security group for WordPress database"
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WordPressDatabaseSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

# EC2 Instances

resource "aws_instance" "wordpress_instance" {
  count         = 3
  ami           = var.wordpress_ami
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  tags = {
    Name        = "WordPressInstance-${count.index}"
    Environment = "production"
    Project     = "wordpress"
  }
}

# RDS Instance

resource "aws_db_instance" "wordpress_database" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.database_instance_class
  db_name              = "wordpress"
  username             = "admin"
  password             = "password123"
  vpc_security_group_ids = [
    aws_security_group.database_sg.id
  ]
  availability_zone = var.availability_zones[0]
  skip_final_snapshot = true
  tags = {
    Name        = "WordPressDatabase"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Elastic Load Balancer

resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]
  tag {
    key   = "Name"
    value = "WordPressELB"
  }
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
}

# Auto Scaling Group

resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "WordPressASG"
  launch_configuration = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier = aws_subnet.public_subnets.*.id
  min_size             = 3
  max_size             = 10
  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "WordPressLaunchConfig"
  image_id      = var.wordpress_ami
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  key_name = var.ssh_key_name
}

# CloudFront Distribution

resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
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
    acm_certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn
    ssl_support_method  = "sni-only"
  }
}

# ACM Certificate

resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn = aws_acm_certificate.cert.arn
  validation_record {
    name    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_name
    value   = aws_acm_certificate.cert.domain_validation_options.0.resource_record_value
    type    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_type
  }
}

# Route 53

resource "aws_route53_zone" "wordpress_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_distribution.zone_id
    evaluate_target_health = false
  }
}

# S3 Bucket

resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.bucket_name
  acl    = "private"
  tags = {
    Name        = "WordPressBucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

# Outputs

output "ec2_instance_ids" {
  value = aws_instance.wordpress_instance.*.id
}

output "rds_instance_id" {
  value = aws_db_instance.wordpress_database.id
}

output "elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_distribution.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.wordpress_bucket.id
}

output "route53_zone_id" {
  value = aws_route53_zone.wordpress_zone.id
}
