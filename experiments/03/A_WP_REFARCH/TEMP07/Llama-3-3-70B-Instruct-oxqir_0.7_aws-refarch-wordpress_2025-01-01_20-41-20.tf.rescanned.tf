# Specify the provider and version
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

# VPC Configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  cidr_block = var.public_subnet_cidr_block
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = var.public_subnet_availability_zone
  tags = {
    Name        = "PublicSubnet"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  cidr_block = var.private_subnet_cidr_block
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = var.private_subnet_availability_zone
  tags = {
    Name        = "PrivateSubnet"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PublicRouteTable"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Public Route
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate Public Subnet with Public Route Table
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow HTTP, HTTPS, and SSH"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
    description = "HTTP from Admin IP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
    description = "HTTPS from Admin IP"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
    description = "SSH from Admin IP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All traffic to all IP addresses"
  }

  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow MySQL/Aurora"
  vpc_id      = aws_vpc.wordpress_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
    description     = "MySQL/Aurora from Web Server SG"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All traffic to all IP addresses"
  }

  tags = {
    Name        = "WordPressRDSSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 Instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = var.wordpress_ami
  instance_type = var.wordpress_instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnet.id
  key_name = var.key_name
  user_data = file("${path.module}/user_data.sh")
  associate_public_ip_address = false
  monitoring = true
  ebs_optimized = true
  tags = {
    Name        = "WordPressInstance"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# RDS Instance for WordPress Database
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = var.rds_allocated_storage
  engine               = var.rds_engine
  engine_version       = var.rds_engine_version
  instance_class       = var.rds_instance_class
  name                 = var.rds_name
  username             = var.rds_username
  password             = var.rds_password
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  storage_encrypted = true
  backup_retention_period = 12
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  tags = {
    Name        = "WordPressRDS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "WordPressRDSGroup"
  subnet_ids = [aws_subnet.private_subnet.id]

  tags = {
    Name        = "WordPressRDSGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "WordPressELB"
  subnets         = [aws_subnet.public_subnet.id]
  security_groups = [aws_security_group.web_server_sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 443
    instance_protocol  = "https"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = var.ssl_certificate_id
  }

  access_logs {
    bucket        = aws_s3_bucket.wordpress_bucket.id
    bucket_prefix = "elb-logs"
    interval      = 60
  }

  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "WordPressASG"
  max_size                  = var.asg_max_size
  min_size                  = var.asg_min_size
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity         = var.asg_desired_capacity
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = aws_subnet.public_subnet.id
  load_balancers            = [aws_elb.wordpress_elb.name]

  tag {
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }

  tags = {
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "WordPressLC"
  image_id      = var.wordpress_ami
  instance_type = var.wordpress_instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.web_server_sg.id]
  user_data = file("${path.module}/user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }

  enabled = true

  default_root_object = "index.html"

  aliases = [var.domain_name]

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

    viewer_protocol_policy = "https-only"
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
    acm_certificate_arn = var.ssl_certificate_id
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  logging_config {
    bucket = aws_s3_bucket.wordpress_bucket.id
    prefix = "cdn-logs"
  }

  tags = {
    Name        = "WordPressCDN"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = var.bucket_name
  acl    = "private"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.wordpress_bucket.id
    target_prefix = "/logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Name        = "WordPressBucket"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_record" "wordpress_record" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cdn.zone_id
    evaluate_target_health = false
  }
}

# Variables
variable "region" {
  type        = string
  default     = "us-west-2"
  description = "AWS Region"
}

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR Block"
}

variable "public_subnet_cidr_block" {
  type        = string
  default     = "10.0.1.0/24"
  description = "Public Subnet CIDR Block"
}

variable "private_subnet_cidr_block" {
  type        = string
  default     = "10.0.2.0/24"
  description = "Private Subnet CIDR Block"
}

variable "public_subnet_availability_zone" {
  type        = string
  default     = "us-west-2a"
  description = "Public Subnet Availability Zone"
}

variable "private_subnet_availability_zone" {
  type        = string
  default     = "us-west-2b"
  description = "Private Subnet Availability Zone"
}

variable "admin_ip" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Admin IP Address"
}

variable "wordpress_ami" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "WordPress AMI"
}

variable "wordpress_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "WordPress Instance Type"
}

variable "key_name" {
  type        = string
  default     = "wordpress_key"
  description = "Key Name"
}

variable "rds_allocated_storage" {
  type        = number
  default     = 20
  description = "RDS Allocated Storage"
}

variable "rds_engine" {
  type        = string
  default     = "mysql"
  description = "RDS Engine"
}

variable "rds_engine_version" {
  type        = string
  default     = "8.0.28"
  description = "RDS Engine Version"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "RDS Instance Class"
}

variable "rds_name" {
  type        = string
  default     = "wordpressdb"
  description = "RDS Name"
}

variable "rds_username" {
  type        = string
  default     = "wordpressuser"
  description = "RDS Username"
}

variable "rds_password" {
  type        = string
  sensitive   = true
  description = "RDS Password"
}

variable "ssl_certificate_id" {
  type        = string
  default     = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  description = "SSL Certificate ID"
}

variable "asg_max_size" {
  type        = number
  default     = 5
  description = "ASG Max Size"
}

variable "asg_min_size" {
  type        = number
  default     = 1
  description = "ASG Min Size"
}

variable "asg_desired_capacity" {
  type        = number
  default     = 2
  description = "ASG Desired Capacity"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain Name"
}

variable "route53_zone_id" {
  type        = string
  default     = "Z123456789012"
  description = "Route 53 Zone ID"
}

variable "bucket_name" {
  type        = string
  default     = "wordpress-bucket"
  description = "Bucket Name"
}

# Outputs
output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "WordPress ELB DNS Name"
}

output "wordpress_cdn_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
  description = "WordPress CDN Domain Name"
}

output "wordpress_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.bucket
  description = "WordPress Bucket Name"
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "WordPress RDS Endpoint"
}

output "wordpress_rds_username" {
  value       = aws_db_instance.wordpress_rds.username
  description = "WordPress RDS Username"
}

output "wordpress_rds_password" {
  value       = aws_db_instance.wordpress_rds.password
  sensitive   = true
  description = "WordPress RDS Password"
}
