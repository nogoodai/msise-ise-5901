# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "AWS Region"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "Public Subnet CIDRs"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "Private Subnet CIDRs"
}

variable "web_server_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Web Server Instance Type"
}

variable "rds_instance_type" {
  type        = string
  default     = "db.t2.small"
  description = "RDS Instance Type"
}

variable "domain_name" {
  type        = string
  default     = "example.com"
  description = "Domain Name"
}

# VPC and Networking Resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  enable_flow_log = true
  tags = {
    Name        = "WordPressVPC"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name        = "PublicSubnet${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 2
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = "us-west-2${count.index + 1}"
  tags = {
    Name        = "PrivateSubnet${count.index + 1}"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "Production"
    Project     = "WordPress"
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
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route_table_association" "public_subnets" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Groups
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Allow inbound HTTP and HTTPS traffic from a specific IP range"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "HTTP from VPC"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "HTTPS from VPC"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All traffic out"
  }
  tags = {
    Name        = "WordPressWebServerSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Allow inbound MySQL traffic from web server"
  vpc_id      = aws_vpc.wordpress_vpc.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_server_sg.id]
    description     = "MySQL from web server"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All traffic out"
  }
  tags = {
    Name        = "WordPressRDSSG"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# EC2 Instances for WordPress
resource "aws_instance" "wordpress_instance" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.web_server_instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[0].id
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
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.20"
  instance_class       = var.rds_instance_type
  name                 = "wordpressdb"
  username             = "wordpressuser"
  password             = random_password.wordpress_rds_password.result
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  storage_encrypted = true
  backup_retention_period = 12
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  iam_database_authentication_enabled = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "random_password" "wordpress_rds_password" {
  length = 16
  special = true
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = aws_subnet.private_subnets[*].id
  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets[*].id
  security_groups = [aws_security_group.web_server_sg.id]
  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 80
    lb_protocol        = "http"
  }
  access_logs {
    bucket        = aws_s3_bucket.wordpress_elb_logs.id
    bucket_prefix = "elb-logs"
    interval      = 60
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_elb_logs" {
  bucket = "wordpress-elb-logs"
  acl    = "private"
  tags = {
    Name        = "WordPressELBLogs"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Auto Scaling Group for EC2 Instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size            = 1
  max_size            = 3
  vpc_zone_identifier = aws_subnet.public_subnets[0].id
  load_balancers = [
    aws_elb.wordpress_elb.name
  ]
  tags = [
    {
      key                 = "Name"
      value               = "WordPressASG"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "Production"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "WordPress"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.web_server_instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  user_data = file("${path.module}/user_data.sh")
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "wordpress-elb"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
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
    acm_certificate_arn = aws_acm_certificate.wordpress_acm.arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
  logging_config {
    bucket = aws_s3_bucket.wordpress_cdn_logs.id
    prefix = "cdn-logs"
    include_cookies = false
    bucket_prefix = "cdn-logs"
  }
  tags = {
    Name        = "WordPressCDN"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_acm_certificate" "wordpress_acm" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags = {
    Name        = "WordPressACM"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_route53_record" "wordpress_route53" {
  zone_id = aws_route53_zone.wordpress_route53_zone.id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.wordpress_cdn.domain_name
    zone_id               = aws_cloudfront_distribution.wordpress_cdn.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_zone" "wordpress_route53_zone" {
  name = var.domain_name
  tags = {
    Name        = "WordPressRoute53"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# S3 Bucket for Static Assets
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = var.domain_name
  acl    = "private"
  versioning {
    enabled = true
  }
  logging {
    target_bucket = aws_s3_bucket.wordpress_s3_logs.id
    target_prefix = "s3-logs"
  }
  tags = {
    Name        = "WordPressS3"
    Environment = "Production"
    Project     = "WordPress"
  }
}

resource "aws_s3_bucket" "wordpress_s3_logs" {
  bucket = "wordpress-s3-logs"
  acl    = "private"
  tags = {
    Name        = "WordPressS3Logs"
    Environment = "Production"
    Project     = "WordPress"
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the WordPress ELB"
}

output "wordpress_rds_endpoint" {
  value       = aws_db_instance.wordpress_rds.endpoint
  description = "The endpoint of the WordPress RDS instance"
}

output "wordpress_cdn_domain_name" {
  value       = aws_cloudfront_distribution.wordpress_cdn.domain_name
  description = "The domain name of the WordPress CloudFront distribution"
}
