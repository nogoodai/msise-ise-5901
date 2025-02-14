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
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "The CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "The CIDR block for the private subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "ssh_cidr" {
  description = "CIDR block that is allowed to connect to EC2 instances via SSH."
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_engine" {
  description = "The database engine for RDS."
  type        = string
  default     = "mysql"
}

variable "db_instance_class" {
  description = "The instance class for RDS."
  type        = string
  default     = "db.t2.small"
}

variable "ami_id" {
  description = "The AMI ID for the WordPress EC2 instances."
  type        = string
  default     = "ami-0c55b159cbfafe1f0" # Replace with desired AMI
}

resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = false  # Secured by disabling public IP assignment
  availability_zone       = "${var.region}a"
  tags = {
    Name        = "WordPressPublicSubnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.region}a"
  tags = {
    Name        = "WordPressPrivateSubnet"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "WordPressPublicRouteTable"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
    description = "Allow SSH from specified CIDR"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "WordPressWebSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
    description     = "Allow MySQL access from web servers"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  tags = {
    Name        = "WordPressDBSG"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_rds_instance" "wordpress_db" {
  engine               = var.db_engine
  instance_class       = var.db_instance_class
  allocated_storage    = 20
  name                 = "wordpress"
  username             = var.db_username
  password             = var.db_password
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  multi_az             = true
  tags = {
    Name        = "WordPressDB"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_elb" "wordpress_elb" {
  availability_zones = [aws_subnet.public_subnet.availability_zone]
  listeners {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }
  listeners {
    instance_port     = 443
    instance_protocol = "HTTPS"
    lb_port           = 443
    lb_protocol       = "HTTPS"
    ssl_certificate_id = "arn:aws:iam::123456789012:server-certificate/your-cert-name"
  }
  security_groups = [aws_security_group.web_sg.id]
  subnets         = [aws_subnet.public_subnet.id]
  access_logs {
    bucket = aws_s3_bucket.wordpress_assets.id
    enabled = true
    interval = 60
    prefix = "elb-logs"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-configuration"
  image_id      = var.ami_id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              EOF
}

resource "aws_autoscaling_group" "wordpress_asg" {
  desired_capacity     = 2
  max_size             = 4
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.public_subnet.id]
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  load_balancers       = [aws_elb.wordpress_elb.id]
  tags = [{
    key                 = "Name"
    value               = "WordPressASG"
    propagate_at_launch = true
  }]
}

resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    target_origin_id       = "wordpress-elb"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    minimum_protocol_version       = "TLSv1.2_2019"
    ssl_support_method             = "sni-only"
  }

  web_acl_id = var.waf_web_acl_id

  logging_config {
    bucket = aws_s3_bucket.wordpress_assets.id
    include_cookies = false
    prefix = "cloudfront-logs/"
  }

  tags = {
    Name        = "WordPressCloudFront"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_s3_bucket" "wordpress_assets" {
  bucket = "wordpress-assets-${random_id.bucket_suffix.hex}"
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket_logging.id
    target_prefix = "s3-access-logs/"
  }
  tags = {
    Name        = "WordPressAssetsBucket"
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
  tags = {
    Environment = "production"
    Project     = "wordpress"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cf.domain_name
    zone_id                = aws_cloudfront_distribution.wordpress_cf.hosted_zone_id
    evaluate_target_health = false
  }
}

output "wordpress_elb_dns" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "DNS name of the WordPress ELB"
}

output "wordpress_cf_domain" {
  value       = aws_cloudfront_distribution.wordpress_cf.domain_name
  description = "Domain name of the WordPress CloudFront distribution"
}

output "wordpress_db_endpoint" {
  value       = aws_rds_instance.wordpress_db.endpoint
  description = "Endpoint of the WordPress RDS DB instance"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_assets.id
  description = "Name of the S3 bucket for WordPress assets"
}

variable "db_username" {
  description = "The username for the RDS database."
  type        = string
}

variable "db_password" {
  description = "The password for the RDS database."
  type        = string
}

variable "acm_certificate_arn" {
  description = "The ARN of the ACM certificate for CloudFront."
  type        = string
}

variable "waf_web_acl_id" {
  description = "The ID of the WAF Web ACL to associate with the CloudFront distribution."
  type        = string
}
