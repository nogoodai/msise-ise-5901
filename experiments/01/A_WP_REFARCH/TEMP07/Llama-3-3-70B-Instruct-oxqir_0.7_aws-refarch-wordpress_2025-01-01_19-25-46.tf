# Terraform configuration for AWS resources
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

# Variables for user-configurable values
variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for VPC"
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

# VPC configuration
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "WordPressVPC"
  }
}

# Subnets configuration
resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PublicSubnet1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "PublicSubnet2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name = "PrivateSubnet1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name = "PrivateSubnet2"
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
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Route table associations
resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_1_association" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2_association" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security groups configuration
resource "aws_security_group" "web_server_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  name   = "WebServerSG"
  description = "Security group for web server instances"
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
    Name = "WebServerSG"
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id
  name   = "DBSG"
  description = "Security group for database instances"
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
    Name = "DBSG"
  }
}

# EC2 instances for WordPress
resource "aws_instance" "wordpress_instance_1" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnet_1.id
  key_name = "wordpress_key"
  tags = {
    Name = "WordPressInstance1"
  }
}

resource "aws_instance" "wordpress_instance_2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  subnet_id = aws_subnet.public_subnet_2.id
  key_name = "wordpress_key"
  tags = {
    Name = "WordPressInstance2"
  }
}

# RDS instance for WordPress database
resource "aws_db_instance" "wordpress_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = var.db_instance_class
  db_name              = "wordpressdb"
  username             = "wordpressuser"
  password             = "wordpresspassword"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  tags = {
    Name = "WordPressDB"
  }
}

# DB subnet group
resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress_db_subnet_group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  tags = {
    Name = "WordPressDBSubnetGroup"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  security_groups = [aws_security_group.web_server_sg.id]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port          = 80
    lb_protocol      = "http"
  }
  listener {
    instance_port     = 443
    instance_protocol = "https"
    lb_port          = 443
    lb_protocol      = "https"
    ssl_certificate_id = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
  tags = {
    Name = "WordPressELB"
  }
}

# Auto Scaling Group for EC2 instances
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 2
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  tags = {
    Name = "WordPressASG"
  }
}

# Launch configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.instance_type
  security_groups = [aws_security_group.web_server_sg.id]
  key_name               = "wordpress_key"
  user_data              = file("user_data.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cfd" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "WordPressELB"
  }
  enabled = true
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
    acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
  tags = {
    Name = "WordPressCFD"
  }
}

# S3 bucket for static assets
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket        = "wordpress-s3-bucket"
  acl           = "private"
  force_destroy = true
  tags = {
    Name = "WordPressS3Bucket"
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
  tags = {
    Name = "WordPressZone"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.id
  name    = "example.com"
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

output "wordpress_cfd_domain_name" {
  value = aws_cloudfront_distribution.wordpress_cfd.domain_name
}

output "wordpress_s3_bucket_arn" {
  value = aws_s3_bucket.wordpress_s3_bucket.arn
}

output "wordpress_zone_id" {
  value = aws_route53_zone.wordpress_zone.id
}
