# Required provider configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0"
    }
  }
}

# Configure the AWS provider
provider "aws" {
  region = "us-west-2"
}

# Variables for easier configuration
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
}

variable "aws_availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "Availability zones for VPC"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "database_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "domain_name" {
  type        = string
  description = "Domain name for Route 53 and CloudFront"
}

# VPC configuration
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

# Internet gateway configuration
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

# Public subnets configuration
resource "aws_subnet" "public" {
  count             = length(var.aws_availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  vpc_id            = aws_vpc.this.id
  availability_zone = var.aws_availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name        = "WordPressPublicSubnet-${var.aws_availability_zones[count.index]}"
    Environment = "production"
  }
}

# Private subnets configuration
resource "aws_subnet" "private" {
  count             = length(var.aws_availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, length(var.aws_availability_zones) + count.index)
  vpc_id            = aws_vpc.this.id
  availability_zone = var.aws_availability_zones[count.index]
  tags = {
    Name        = "WordPressPrivateSubnet-${var.aws_availability_zones[count.index]}"
    Environment = "production"
  }
}

# Public route table configuration
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = "production"
  }
}

# Private route table configuration
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name        = "WordPressPrivateRouteTable"
    Environment = "production"
  }
}

# Route table associations
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Internet gateway route configuration
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# Security group configuration
resource "aws_security_group" "web_server" {
  vpc_id = aws_vpc.this.id
  name   = "WordPressWebServerSG"
  description = "Allow inbound traffic on ports 80 and 443"
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
    Name        = "WordPressWebServerSG"
    Environment = "production"
  }
}

resource "aws_security_group" "database" {
  vpc_id = aws_vpc.this.id
  name   = "WordPressDatabaseSG"
  description = "Allow inbound traffic on port 3306 from web server security group"
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server.id]
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
  }
}

# EC2 instance configuration
resource "aws_instance" "this" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server.id]
  tags = {
    Name        = "WordPressEC2Instance"
    Environment = "production"
  }
}

# RDS instance configuration
resource "aws_db_instance" "this" {
  instance_class = var.database_instance_class
  engine         = "mysql"
  username       = "wordpress"
  password       = "password"
  vpc_security_group_ids = [aws_security_group.database.id]
  tags = {
    Name        = "WordPressRDSInstance"
    Environment = "production"
  }
}

# Elastic Load Balancer configuration
resource "aws_elb" "this" {
  name            = "WordPressELB"
  subnets         = aws_subnet.public.*.id
  security_groups = [aws_security_group.web_server.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
  }
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "this" {
  name                 = "WordPressASG"
  launch_configuration = aws_launch_configuration.this.name
  min_size             = 1
  max_size             = 3
  vpc_zone_identifier  = aws_subnet.private.*.id
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASGInstance"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "production"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "this" {
  name          = "WordPressLC"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server.id]
  user_data = "#!/bin/bash\necho 'Hello World' > index.html\nnohup busybox httpd -f -p 80 &"
}

# CloudFront distribution configuration
resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  default_root_object = "index.html"
  aliases         = [var.domain_name]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "my-origin"
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
  origin {
    domain_name = aws_elb.this.dns_name
    origin_id   = "my-origin"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.this.certificate_arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn = aws_acm_certificate.this.arn
  validation_record {
    name    = aws_acm_certificate.this.domain_validation_options[0].resource_record_name
    value   = aws_acm_certificate.this.domain_validation_options[0].resource_record_value
    type    = aws_acm_certificate.this.domain_validation_options[0].resource_record_type
  }
}

resource "aws_route53_record" "this" {
  name    = var.domain_name
  type    = "A"
  zone_id = aws_route53_zone.this.id
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id               = aws_cloudfront_distribution.this.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "this" {
  name = var.domain_name
}

# S3 bucket configuration
resource "aws_s3_bucket" "this" {
  bucket = var.domain_name
  acl    = "private"
  tags = {
    Name        = var.domain_name
    Environment = "production"
  }
}

output "ec2_instance_id" {
  value       = aws_instance.this.id
  description = "ID of the EC2 instance"
}

output "rds_instance_id" {
  value       = aws_db_instance.this.id
  description = "ID of the RDS instance"
}

output "elb_dns_name" {
  value       = aws_elb.this.dns_name
  description = "DNS name of the ELB"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.this.id
  description = "ID of the CloudFront distribution"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.this.bucket
  description = "Name of the S3 bucket"
}
