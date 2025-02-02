terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  default     = "us-west-2"
  description = "AWS region to deploy resources"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment to deploy resources"
}

variable "project" {
  type        = string
  default     = "wordpress"
  description = "Project name to deploy resources"
}

# VPC and networking resources
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "${var.project}-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-igw"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "${var.project}-public-subnet-1"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name        = "${var.project}-public-subnet-2"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-west-2a"
  tags = {
    Name        = "${var.project}-private-subnet-1"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-west-2b"
  tags = {
    Name        = "${var.project}-private-subnet-2"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-public-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-private-route-table"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.wordpress_igw.id
}

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

# Security groups
resource "aws_security_group" "wordpress_ec2_sg" {
  name        = "${var.project}-ec2-sg"
  description = "Security group for WordPress EC2 instances"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-ec2-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group_rule" "wordpress_ec2_sg_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.wordpress_ec2_sg.id
}

resource "aws_security_group_rule" "wordpress_ec2_sg_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.wordpress_ec2_sg.id
}

resource "aws_security_group" "wordpress_rds_sg" {
  name        = "${var.project}-rds-sg"
  description = "Security group for WordPress RDS instance"
  vpc_id      = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-rds-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_security_group_rule" "wordpress_rds_sg_ingress_mysql" {
  type                     = "ingress"
  from_port                 = 3306
  to_port                   = 3306
  protocol                  = "tcp"
  source_security_group_id = aws_security_group.wordpress_ec2_sg.id
  security_group_id        = aws_security_group.wordpress_rds_sg.id
}

# EC2 instances
resource "aws_instance" "wordpress_ec2" {
  ami           = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  subnet_id = aws_subnet.public_subnet_1.id
  tags = {
    Name        = "${var.project}-ec2"
    Environment = var.environment
    Project     = var.project
  }
}

# RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  vpc_security_group_ids = [
    aws_security_group.wordpress_rds_sg.id
  ]
  db_subnet_group_name = aws_db_subnet_group.wordpress_rds_subnet_group.name
  tags = {
    Name        = "${var.project}-rds"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "${var.project}-rds-subnet-group"
  subnet_ids = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id
  ]
  tags = {
    Name        = "${var.project}-rds-subnet-group"
    Environment = var.environment
    Project     = var.project
  }
}

# Elastic Load Balancer
resource "aws_alb" "wordpress_alb" {
  name            = "${var.project}-alb"
  subnets         = [
    aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id
  ]
  security_groups = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  tags = {
    Name        = "${var.project}-alb"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_alb_target_group" "wordpress_alb_target_group" {
  name     = "${var.project}-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  tags = {
    Name        = "${var.project}-alb-target-group"
    Environment = var.environment
    Project     = var.project
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "${var.project}-asg"
  max_size            = 2
  min_size            = 1
  desired_capacity    = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"
  force_delete              = true
  launch_configuration      = aws_launch_configuration.wordpress_lc.name
  vpc_zone_identifier       = [
    aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id
  ]
  tags = [
    {
      key                 = "Name"
      value               = "${var.project}-asg"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = var.project
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "${var.project}-lc"
  image_id      = "ami-0c94855ba95c71c99"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.wordpress_ec2_sg.id
  ]
  key_name               = "wordpress-ec2-key"
  user_data              = file("${path.module}/wordpress-install.sh")
  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "wordpress_cf" {
  origin {
    domain_name = aws_alb.wordpress_alb.dns_name
    origin_id   = aws_alb.wordpress_alb.id
  }
  enabled             = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_alb.wordpress_alb.id
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
  tags = {
    Name        = "${var.project}-cf"
    Environment = var.environment
    Project     = var.project
  }
}

# S3 bucket
resource "aws_s3_bucket" "wordpress_s3" {
  bucket        = "${var.project}-s3"
  acl           = "private"
  force_destroy = true
  tags = {
    Name        = "${var.project}-s3"
    Environment = var.environment
    Project     = var.project
  }
}

# Route 53 DNS configuration
resource "aws_route53_zone" "wordpress_r53" {
  name = "${var.project}.com"
}

resource "aws_route53_record" "wordpress_r53_record" {
  zone_id = aws_route53_zone.wordpress_r53.id
  name    = "${var.project}.com"
  type    = "A"
  alias {
    name                   = aws_alb.wordpress_alb.dns_name
    zone_id                = aws_alb.wordpress_alb.zone_id
    evaluate_target_health = false
  }
}

# Outputs
output "wordpress_vpc_id" {
  value = aws_vpc.wordpress_vpc.id
}

output "wordpress_alb_dns_name" {
  value = aws_alb.wordpress_alb.dns_name
}

output "wordpress_rds_endpoint" {
  value = aws_db_instance.wordpress_rds.endpoint
}

output "wordpress_cf_distribution_id" {
  value = aws_cloudfront_distribution.wordpress_cf.id
}

output "wordpress_s3_bucket_name" {
  value = aws_s3_bucket.wordpress_s3.bucket
}

output "wordpress_r53_zone_id" {
  value = aws_route53_zone.wordpress_r53.id
}
