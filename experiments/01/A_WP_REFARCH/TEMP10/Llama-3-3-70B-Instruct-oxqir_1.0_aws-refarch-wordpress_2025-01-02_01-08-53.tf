# Provider Configuration
terraform {
  required_version = ">= 1.1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.1.0"
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
  description = "AWS region to deploy resources"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}

variable "public_subnets" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "Public subnets CIDR blocks"
}

variable "private_subnets" {
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
  description = "Private subnets CIDR blocks"
}

variable "instance_type" {
  type        = string
  default     = "t2.micro"
  description = "EC2 instance type"
}

variable "ami_id" {
  type        = string
  default     = "ami-0c94855ba95c71c99"
  description = "EC2 instance AMI ID"
}

variable "rds_instance_class" {
  type        = string
  default     = "db.t2.micro"
  description = "RDS instance class"
}

variable "database_name" {
  type        = string
  default     = "wordpress"
  description = "RDS database name"
}

variable "database_user" {
  type        = string
  default     = "wordpressuser"
  description = "RDS database user"
}

variable "database_password" {
  type        = string
  default     = "wordpresspassword"
  description = "RDS database password"
}

# VPC and Networking Resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "wordpress-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = "${var.aws_region}${count.index + 1}"
  tags = {
    Name        = "public-subnet-${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = "${var.aws_region}${count.index + 1}"
  tags = {
    Name        = "private-subnet-${count.index + 1}"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-igw"
    Environment = "production"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "public-route-table"
    Environment = "production"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "private-route-table"
    Environment = "production"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

resource "aws_route_table_association" "public_subnets_association" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnets_association" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "wordpress-ec2-sg"
  description = "Allow inbound traffic on port 80 and 22"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-ec2-sg"
    Environment = "production"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "wordpress-rds-sg"
  description = "Allow inbound traffic on port 3306"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-rds-sg"
    Environment = "production"
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_ec2_sg.id]
  }
}

resource "aws_security_group" "wordpress_elb_sg" {
  name        = "wordpress-elb-sg"
  description = "Allow inbound traffic on port 80 and 443"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-elb-sg"
    Environment = "production"
  }

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
}

# EC2 Instances
resource "aws_instance" "wordpress_ec2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  subnet_id = aws_subnet.private_subnets[0].id
  tags = {
    Name        = "wordpress-ec2"
    Environment = "production"
  }
}

# RDS Instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.rds_instance_class
  name                 = var.database_name
  username             = var.database_user
  password             = var.database_password
  parameter_group_name = "default.mysql5.7"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name       = "wordpress-db-subnet-group"
  subnet_ids = aws_subnet.private_subnets.*.id
  tags = {
    Name        = "wordpress-db-subnet-group"
    Environment = "production"
  }
}

# Elastic Load Balancer
resource "aws_elb" "wordpress_elb" {
  name            = "wordpress-elb"
  subnets         = aws_subnet.public_subnets.*.id
  security_groups = [aws_security_group.wordpress_elb_sg.id]
  tags = {
    Name        = "wordpress-elb"
    Environment = "production"
  }
}

resource "aws_elb_listener" "wordpress_elb_listener" {
  load_balancer_name = aws_elb.wordpress_elb.name
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.wordpress_lb_target_group.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "wordpress_lb_target_group" {
  name     = "wordpress-lb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "wordpress-lb-target-group"
    Environment = "production"
  }
}

resource "aws_lb_target_group_attachment" "wordpress_lb_target_group_attachment" {
  target_group_arn = aws_lb_target_group.wordpress_lb_target_group.arn
  target_id        = aws_instance.wordpress_ec2.id
  port             = 80
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_autoscaling_group" {
  name                      = "wordpress-autoscaling-group"
  launch_configuration_name = aws_launch_configuration.wordpress_launch_configuration.name
  min_size                  = 1
  max_size                  = 3
  vpc_zone_identifier       = aws_subnet.private_subnets.*.id
  tags = [
    {
      key                 = "Name"
      value               = "wordpress-autoscaling-group"
      propagate_at_launch = true
    },
  ]
}

resource "aws_launch_configuration" "wordpress_launch_configuration" {
  name          = "wordpress-launch-configuration"
  image_id      = var.ami_id
  instance_type = var.instance_type
  security_groups = [
    aws_security_group.wordpress_ec2_sg.id,
  ]
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cloudfront_distribution" {
  origin {
    domain_name = aws_elb.wordpress_elb.dns_name
    origin_id   = "wordpress-elb"
  }

  enabled         = true
  is_ipv6_enabled = true

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

# S3 Bucket
resource "aws_s3_bucket" "wordpress_s3_bucket" {
  bucket        = "wordpress-s3-bucket"
  acl           = "private"
  force_destroy = true
  tags = {
    Name        = "wordpress-s3-bucket"
    Environment = "production"
  }
}

# Route 53 DNS Configuration
resource "aws_route53_zone" "wordpress_route53_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_route53_record" {
  zone_id = aws_route53_zone.wordpress_route53_zone.zone_id
  name    = "example.com"
  type    = "A"
  alias {
    name                   = aws_elb.wordpress_elb.dns_name
    zone_id               = aws_elb.wordpress_elb.zone_id
    evaluate_target_health = false
  }
}

output "wordpress_elb_dns_name" {
  value = aws_elb.wordpress_elb.dns_name
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3_bucket.bucket
}

output "wordpress_route53_zone_id" {
  value = aws_route53_zone.wordpress_route53_zone.zone_id
}
