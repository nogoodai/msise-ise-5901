# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables section
variable "aws_region" {
  type        = string
  default     = "us-west-2"
  description = "AWS region to deploy resources"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "subnet1_cidr" {
  type        = string
  default     = "10.0.1.0/24"
  description = "Public subnet CIDR block"
}

variable "subnet2_cidr" {
  type        = string
  default     = "10.0.2.0/24"
  description = "Private subnet CIDR block"
}

variable "aws_instance_type" {
  type        = string
  default     = "t2.micro"
  description = "AWS instance type for EC2 instances"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.small"
  description = "RDS instance class"
}

variable "key_name" {
  type        = string
  description = "AWS Key pair name for SSH access"
}

# Networking section
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  enable_classiclink   = false
  instance_tenancy     = "default"

  tags = {
    Name        = "WordPressVPC"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnet1" {
  cidr_block = var.subnet1_cidr
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "PublicSubnet1"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnet2" {
  cidr_block = var.subnet2_cidr
  vpc_id     = aws_vpc.wordpress_vpc.id
  availability_zone = "us-west-2b"
  map_public_ip_on_launch = false

  tags = {
    Name        = "PrivateSubnet2"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "WordPressIGW"
    Environment = "production"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id

  tags = {
    Name        = "PublicRouteTable"
    Environment = "production"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnet1_association" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.public_route_table.id
}

# Security groups section
resource "aws_security_group" "ec2_sg" {
  name        = "WordPressEC2SG"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id

  # Allow inbound HTTP traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTPS traffic
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound SSH traffic from specific IP ranges
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.0.2.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "WordPressEC2SG"
    Environment = "production"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "WordPressRDSSG"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id

  # Allow inbound MySQL traffic from EC2 security group
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
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
  }
}

# EC2 instances section
resource "aws_instance" "wordpress_ec2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = var.aws_instance_type
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id = aws_subnet.public_subnet1.id
  key_name               = var.key_name

  tags = {
    Name        = "WordPressEC2"
    Environment = "production"
  }
}

# RDS instance section
resource "aws_db_instance" "wordpress_rds" {
  identifier           = "wordpress-rds"
  instance_class       = var.rds_instance_class
  engine               = "mysql"
  engine_version       = "8.0.23"
  username             = "admin"
  password             = "password123"
  parameter_group_name = "default.mysql8.0"
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true

  tags = {
    Name        = "WordPressRDS"
    Environment = "production"
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress-rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet2.id]

  tags = {
    Name        = "WordPressRDSSubnetGroup"
    Environment = "production"
  }
}

# Elastic Load Balancer section
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = [aws_subnet.public_subnet1.id]
  security_groups = [aws_security_group.ec2_sg.id]

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

# Auto Scaling Group section
resource "aws_autoscaling_group" "wordpress_asg" {
  name                      = "wordpress-asg"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_launch_config.name
  vpc_zone_identifier       = [aws_subnet.public_subnet1.id]

  tag {
    key                 = "Name"
    value               = "WordPressEC2"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "wordpress_launch_config" {
  name          = "wordpress-launch-config"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = var.aws_instance_type
  security_groups = [aws_security_group.ec2_sg.id]
  key_name               = var.key_name
  user_data = file("${path.module}/user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution section
resource "aws_cloudfront_distribution" "wordpress_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "WordPress CloudFront distribution"

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
    cloudfront_default_certificate = true
  }
}

# S3 bucket section
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-bucket"
  acl    = "private"

  tags = {
    Name        = "WordPressS3Bucket"
    Environment = "production"
  }
}

# Route 53 DNS configuration section
resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"

  tags = {
    Name        = "WordPressRoute53Zone"
    Environment = "production"
  }
}

resource "aws_route53_record" "wordpress_record" {
  zone_id = aws_route53_zone.wordpress_zone.zone_id
  name    = "example.com"
  type    = "A"

  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

# Outputs section
output "elb_dns_name" {
  value       = aws_elb.wordpress_elb.dns_name
  description = "The DNS name of the Elastic Load Balancer"
}

output "rds_instance_address" {
  value       = aws_db_instance.wordpress_rds.address
  description = "The address of the RDS instance"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.wordpress_bucket.id
  description = "The name of the S3 bucket"
}

output "route53_zone_id" {
  value       = aws_route53_zone.wordpress_zone.id
  description = "The ID of the Route 53 zone"
}
