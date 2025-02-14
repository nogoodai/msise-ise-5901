# Terraform configuration for AWS WordPress architecture

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
  required_version = ">= 1.3.0"
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variables
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
}

variable "public_subnets_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for public subnets"
}

variable "private_subnets_cidr_blocks" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "CIDR blocks for private subnets"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
  description = "Availability zones for subnets"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for EC2 instances"
}

variable "db_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for RDS instance"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain name for Route 53 configuration"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnets_cidr_blocks)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "public-subnet-${count.index}"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets_cidr_blocks)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets_cidr_blocks[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "private-subnet-${count.index}"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "public-route-table"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnets_association" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security groups
resource "aws_security_group" "ec2_security_group" {
  name        = "ec2-security-group"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic from VPC"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow SSH traffic from VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "ec2-security-group"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_security_group" "rds_security_group" {
  name        = "rds-security-group"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_security_group.id]
    description     = "Allow MySQL traffic from EC2 instances"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "rds-security-group"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_security_group" "elb_security_group" {
  name        = "elb-security-group"
  description = "Security group for ELB"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic from VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outgoing traffic"
  }
  tags = {
    Name        = "elb-security-group"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instances" {
  count         = 2
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.ec2_security_group.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true
  tags = {
    Name        = "wordpress-instance-${count.index}"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_rds_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.23"
  instance_class       = var.db_instance_class
  name                 = "wordpressdb"
  username             = "admin"
  password             = random_password.password.result
  vpc_security_group_ids = [
    aws_security_group.rds_security_group.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  storage_encrypted   = true
  backup_retention_period = 12
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  iam_database_authentication_enabled = true
  tags = {
    Name        = "wordpress-rds-instance"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "random_password" "password" {
  length = 16
  special = true
  override_special = "!@#$"
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.elb_security_group.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  access_logs {
    bucket        = aws_s3_bucket.elb_access_logs.id
    bucket_prefix = "elb-access-logs"
    interval      = 60
  }
  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_s3_bucket" "elb_access_logs" {
  bucket        = "elb-access-logs-bucket"
  acl           = "private"
  force_destroy = true
  tags = {
    Name        = "elb-access-logs-bucket"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "wordpress-autoscaling-group"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_configuration.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  load_balancers = [aws_elb.wordpress_elb.name]
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-autoscaling-group"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "production"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "wordpress-architecture"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.ec2_security_group.id
  ]
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution for content delivery
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_s3_bucket.wordpress_s3_bucket.bucket
    origin_id   = "S3Origin"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  logging_config {
    bucket = aws_s3_bucket.cloudfront_logs.id
    prefix = "cloudfront-logs"
  }
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.wordpress_acm_certificate.arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
  web_acl_id = aws_waf_web_acl.wordpress_waf_web_acl.id
  tags = {
    Name        = "wordpress-cloudfront-distribution"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket        = "wordpress-s3-bucket"
  acl           = "private"
  force_destroy = true
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.s3_logs.id
    target_prefix = "s3-logs/"
  }
  tags = {
    Name        = "wordpress-s3-bucket"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_s3_bucket" "s3_logs" {
  bucket        = "s3-logs-bucket"
  acl           = "private"
  force_destroy = true
  tags = {
    Name        = "s3-logs-bucket"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_acm_certificate" "wordpress_acm_certificate" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags = {
    Name        = "wordpress-acm-certificate"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_route53_record" "wordpress_route53_record" {
  name    = var.domain_name
  type    = "A"
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cloudfront_distribution.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.domain_name
  tags = {
    Name        = "wordpress-route53-zone"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_cloudwatch_log_group" "wordpress_cloudwatch_log_group" {
  name = "wordpress-cloudwatch-log-group"
}

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket        = "cloudfront-logs-bucket"
  acl           = "private"
  force_destroy = true
  tags = {
    Name        = "cloudfront-logs-bucket"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_waf_web_acl" "wordpress_waf_web_acl" {
  name        = "wordpress-waf-web-acl"
  metric_name = "wordpress-waf-metric"
  default_action {
    type = "ALLOW"
  }
  rule {
    priority = 1
    rule_id  = aws_waf_rule.wordpress_waf_rule.id
    action {
      type = "BLOCK"
    }
  }
  tags = {
    Name        = "wordpress-waf-web-acl"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_waf_rule" "wordpress_waf_rule" {
  name        = "wordpress-waf-rule"
  metric_name = "wordpress-waf-metric"
  predicate {
    data_id = aws_waf_ipset.wordpress_waf_ipset.id
    negated = false
    type    = "IPMatch"
  }
  tags = {
    Name        = "wordpress-waf-rule"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

resource "aws_waf_ipset" "wordpress_waf_ipset" {
  name = "wordpress-waf-ipset"
  tags = {
    Name        = "wordpress-waf-ipset"
    Environment = "production"
    Project     = "wordpress-architecture"
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the ELB"
}

output "wordpress_cloudfront_distribution_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cloudfront_distribution.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "wordpress_rds_instance_endpoint" {
  value       = aws_db_instance.wordpress_rds_instance.endpoint
  description = "The endpoint of the RDS instance"
}

output "wordpress_autoscaling_group_name" {
  value       = aws_autoscaling_group.wordpress_autoscaling_group.name
  description = "The name of the Auto Scaling group"
}

output "wordpress_s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_s3_bucket.id
  description = "The name of the S3 bucket"
}

output "wordpress_acm_certificate_arn" {
  value       = aws_acm_certificate.wordpress_acm_certificate.arn
  description = "The ARN of the ACM certificate"
}
