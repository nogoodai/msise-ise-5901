# Configure the AWS provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
    }
  }
}

# Provider configuration for AWS
provider "aws" {
  region = "us-west-2"
}

# Variable definitions for user-configurable values
variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC"
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
  description = "Availability zones for the VPC"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "Instance type for the EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "Instance class for the RDS instance"
}

variable "wp_database_username" {
  type        = string
  default     = "wpuser"
  description = "Username for the WordPress database"
}

variable "wp_database_password" {
  type        = string
  sensitive   = true
  description = "Password for the WordPress database"
}

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Subnets configuration
resource "aws_subnet" "public_subnets" {
  count = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PublicSubnet-${count.index}"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_subnet" "private_subnets" {
  count = 3
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 3)
  availability_zone = var.availability_zones[count.index]
  tags = {
    Name        = "PrivateSubnet-${count.index}"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Internet gateway configuration
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Route tables configuration
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.wordpress_igw.id
  }
  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "PrivateRouteTable"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Route table associations
resource "aws_route_table_association" "public_subnets" {
  count = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets" {
  count = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups configuration
resource "aws_security_group" "web_server_sg" {
  name        = "WordPressWebServerSG"
  description = "Security group for the WordPress web server"
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
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["your_ip_address/32"] # replace with your IP address
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
    Project     = "WordPress"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for the WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
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
    Name        = "WordPressRDSSG"
    Environment = "production"
    Project     = "WordPress"
  }
}

# EC2 instances configuration
resource "aws_instance" "wordpress_ec2" {
  count = 3
  ami           = "ami-0c94855ba95c71c99" # replace with your AMI ID
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.web_server_sg.id
  ]
  subnet_id = aws_subnet.public_subnets[count.index].id
  tags = {
    Name        = "WordPressEC2-${count.index}"
    Environment = "production"
    Project     = "WordPress"
  }
}

# RDS instance configuration
resource "aws_db_instance" "wordpress_rds" {
  identifier        = "wordpress-rds"
  engine            = "mysql"
  engine_version    = "8.0.28"
  instance_class    = var.rds_instance_class
  allocated_storage = 20
  storage_type      = "gp2"
  vpc_security_group_ids = [
    aws_security_group.rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_sng.name
  username             = var.wp_database_username
  password             = var.wp_database_password
  parameter_group_name = "default.mysql8.0"
  multi_az             = true
  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
    Project     = "WordPress"
  }
}

# DB subnet group configuration
resource "aws_db_subnet_group" "wordpress_rds_sng" {
  name       = "wordpress-rds-sng"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "WordPressRDSSNG"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Elastic Load Balancer configuration
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.web_server_sg.id]
  listener {
    lb_port       = 80
    lb_protocol   = "http"
    instance_port = 80
    instance_protocol = "http"
  }
  tags = {
    Name        = "WordPressELB"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Auto Scaling Group configuration
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 3
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 3
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lcfg.name
  vpc_zone_identifier       = aws_subnet.public_subnets.*.id
  tag {
    key                 = "Name"
    value               = "WordPressAsg"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = "WordPress"
    propagate_at_launch = true
  }
}

# Launch configuration configuration
resource "aws_launch_configuration" "wordpress_lcfg" {
  name          = "wordpress-lcfg"
  image_id      = "ami-0c94855ba95c71c99" # replace with your AMI ID
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.web_server_sg.id
  ]
  user_data = file("${path.module}/wordpress-install.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution configuration
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["example.com"] # replace with your domain name
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/404.html"
  }
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
    acm_certificate_arn = "arn:aws:acm:REGION:ACCOUNT_ID:certificate/CERTIFICATE_ID" # replace with your ACM certificate ARN
    ssl_support_method  = "sni-only"
  }
}

# S3 bucket configuration
resource "aws_s3_bucket" "wordpress_s3" {
  bucket = "example-bucket" # replace with your bucket name
  acl    = "private"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  tags = {
    Name        = "WordPressS3"
    Environment = "production"
    Project     = "WordPress"
  }
}

# Route 53 configuration
resource "aws_route53_zone" "wordpress_r53" {
  name = "example.com" # replace with your domain name
}

resource "aws_route53_record" "wordpress_r53" {
  zone_id = aws_route53_zone.wordpress_r53.id
  name    = "example.com" # replace with your domain name
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

output "wordpress_r53_zone_id" {
  value = aws_route53_zone.wordpress_r53.id
}

output "wordpress_cfd_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}
